import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:instrument_pos/core/app_restart.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/security/passwords.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';
import 'package:instrument_pos/features/auth/data/auth_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// A problem with exporting or restoring the database that the UI surfaces
/// to the user (invalid file, newer-version backup, …).
class BackupException implements Exception {
  BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Exports consistent snapshots of the live SQLite database (§29 local
/// backup) and orchestrates restoring a backup file over the live one.
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  /// Absolute path of the open database file ('' for in-memory databases,
  /// which cannot be exported).
  Future<String> currentDatabasePath() async {
    final rows = await _db.customSelect('PRAGMA database_list').get();
    for (final row in rows) {
      if (row.data['name'] == 'main') {
        return (row.data['file'] as String?) ?? '';
      }
    }
    return '';
  }

  /// Writes a consistent snapshot of the database to [destinationPath] using
  /// `VACUUM INTO`, then records the BACKUP audit entry (logged first so the
  /// exported file contains it too).
  Future<void> exportBackup({
    required String destinationPath,
    required String actingUserId,
  }) async {
    final livePath = await currentDatabasePath();
    if (livePath.isEmpty) {
      throw BackupException('In-memory databases cannot be exported.');
    }
    if (_samePath(destinationPath, livePath)) {
      throw BackupException(
        'Choose a different file — that is the live database itself.',
      );
    }
    final escaped = destinationPath.replaceAll('\\', '/').replaceAll("'", "''");
    // Log first so the exported snapshot contains the BACKUP audit entry,
    // then write the snapshot. VACUUM INTO must not run inside a transaction.
    await AuditRepository(_db).log(
      action: AuditAction.backup,
      userId: actingUserId,
      entityType: 'database',
      details: 'Exported to ${_fileName(destinationPath)}',
    );
    // VACUUM INTO refuses to overwrite, so clear any previous export.
    final destination = File(destinationPath);
    if (await destination.exists()) await destination.delete();
    await _db.customStatement("VACUUM INTO '$escaped'");
  }

  /// Performs a mandatory full export of the database to [backupDestinationPath],
  /// then wipes all data tables in a transaction and resets the app.
  /// Preserves or re-creates the owner account so the store can be logged into after wiping.
  Future<void> wipeDataWithBackup({
    required String backupDestinationPath,
    required String actingUserId,
    required String actingUsername,
  }) async {
    // 1. Mandatory Backup First
    await exportBackup(
      destinationPath: backupDestinationPath,
      actingUserId: actingUserId,
    );

    // 2. Wipe All Data inside Transaction
    await _db.transaction(() async {
      await _db.delete(_db.exchanges).go();
      await _db.delete(_db.refundItems).go();
      await _db.delete(_db.refunds).go();
      await _db.delete(_db.payments).go();
      await _db.delete(_db.saleItems).go();
      await _db.delete(_db.sales).go();
      await _db.delete(_db.stockMovements).go();
      await _db.delete(_db.products).go();
      await _db.delete(_db.categories).go();
      await _db.delete(_db.brands).go();
      await _db.delete(_db.suppliers).go();
      await _db.delete(_db.importBatches).go();
      await _db.delete(_db.settings).go();
      await _db.delete(_db.auditLogs).go();

      // Ensure owner user exists so store is accessible
      final users = await _db.select(_db.users).get();
      if (users.isEmpty) {
        final authRepo = DriftAuthRepository(_db);
        await authRepo.createUser(
          username: kDefaultOwnerUsername,
          displayName: 'Store Owner',
          role: 'OWNER',
          password: kDefaultOwnerPassword,
        );
      }

      // Mark sample catalog as seeded so auto-seeder doesn't re-seed sample products after wipe
      await _db.into(_db.settings).insertOnConflictUpdate(
        SettingsCompanion(
          key: const Value('sampleCatalogSeeded'),
          value: const Value('1'),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });

    // 3. Log Wipe Audit Action & Restart App
    try {
      final actor = await (_db.select(_db.users)..where(
        (u) => u.username.lower().equals(actingUsername.toLowerCase()),
      )).getSingleOrNull();

      await AuditRepository(_db).log(
        action: 'WIPE_DATA',
        userId: actor?.id,
        entityType: 'database',
        details: 'Wiped all database records after mandatory backup to ${_fileName(backupDestinationPath)}',
      );
    } catch (_) {}

    appRestartCount.value++;
  }

  bool _samePath(String a, String b) =>
      File(a).absolute.path == File(b).absolute.path;
}

/// Replaces the live database file with [sourcePath] and restarts the app so
/// every provider reopens the restored database.
///
/// Ordering matters: the live connection is closed first, stale WAL/shm
/// sidecars are removed, the backup is copied over, and a RESTORE audit row
/// is appended to the restored database (resolving the actor by username —
/// the backup may not contain the current user id) before the app restarts.
Future<void> restoreDatabaseFromBackup({
  required AppDatabase db,
  required String currentPath,
  required String sourcePath,
  required String actingUsername,
}) async {
  // Preflight before touching anything: readable file, not newer than this
  // app understands, and not the live database itself.
  final live = File(currentPath).absolute.path;
  final source = File(sourcePath).absolute.path;
  if (source == live) {
    throw BackupException('That file is the live database itself.');
  }
  if (!await File(sourcePath).exists()) {
    throw BackupException('The backup file does not exist.');
  }
  late final sqlite.Database probe;
  try {
    probe = sqlite.sqlite3.open(sourcePath);
  } on sqlite.SqliteException catch (e) {
    throw BackupException('Not a valid database file (${e.message}).');
  }
  try {
    final version =
        probe.select('PRAGMA user_version').first['user_version'] as int? ?? 0;
    if (version > AppDatabase.currentSchemaVersion) {
      throw BackupException(
        'This backup was made by a newer version of the app and cannot be '
        'restored here.',
      );
    }
  } finally {
    probe.dispose();
  }

  // Swap the files.
  await db.close();
  for (final suffix in ['-wal', '-shm']) {
    final sidecar = File('$currentPath$suffix');
    if (await sidecar.exists()) {
      try {
        await sidecar.delete();
      } catch (_) {}
    }
  }

  Object? copyError;
  for (var i = 0; i < 5; i++) {
    try {
      await File(sourcePath).copy(currentPath);
      copyError = null;
      break;
    } catch (e) {
      copyError = e;
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }
  if (copyError != null) {
    throw BackupException('Could not replace database file ($copyError).');
  }

  // Append the RESTORE audit entry from a throwaway connection; if this ever
  // fails the app restarts anyway and the login screen reports the issue.
  try {
    final restored = AppDatabase(NativeDatabase(File(currentPath)));
    try {
      final actor =
          await (restored.select(restored.users)..where(
                (u) => u.username.lower().equals(actingUsername.toLowerCase()),
              ))
              .getSingleOrNull();
      await AuditRepository(restored).log(
        action: AuditAction.restore,
        userId: actor?.id,
        entityType: 'database',
        details: 'Restored from ${_fileName(sourcePath)}',
      );
    } finally {
      await restored.close();
    }
  } catch (_) {
    // Restart anyway; the restored file is in place.
  }
  appRestartCount.value++;
}

String _fileName(String path) => path.split(Platform.pathSeparator).last;
