import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/app_restart.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/workstation_config.dart';
import 'package:instrument_pos/core/security/passwords.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';
import 'package:instrument_pos/features/auth/data/auth_repository.dart';
import 'package:instrument_pos/features/settings/data/database_backup_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late Directory temp;
  late String livePath;
  late String backupPath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pos_backup_test');
    livePath = '${temp.path}${Platform.pathSeparator}instrument_pos.sqlite';
    backupPath = '${temp.path}${Platform.pathSeparator}backup.db';
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } on FileSystemException {
      // A database handle may still hold the file on Windows; harmless.
    }
  });

  Future<AppDatabase> openLive() =>
      Future.value(AppDatabase(NativeDatabase(File(livePath))));

  test(
    'exportBackup writes a snapshot with data and the BACKUP audit row',
    () async {
      final db = await openLive();
      addTearDown(db.close);
      final auth = DriftAuthRepository(db);
      final cashier = await auth.createUser(
        username: 'ama',
        displayName: 'Ama',
        role: 'CASHIER',
        password: 'secret1',
      );

      final service = BackupService(db);
      expect(await service.currentDatabasePath(), livePath);
      await service.exportBackup(
        destinationPath: backupPath,
        actingUserId: cashier.id,
      );

      expect(File(backupPath).existsSync(), isTrue);

      // The exported file is a real database containing the data and the audit
      // entry (audit is logged before the snapshot is written).
      final exported = AppDatabase(NativeDatabase(File(backupPath)));
      addTearDown(exported.close);
      final users = await exported.select(exported.users).get();
      expect(users.map((u) => u.username), contains('ama'));
      final logs = await exported.select(exported.auditLogs).get();
      expect(logs.map((l) => l.action), contains(AuditAction.backup));
    },
  );

  test(
    'restore swaps the file and the app restarts with restored data',
    () async {
      final db = await openLive();
      final auth = DriftAuthRepository(db);
      final cashier = await auth.createUser(
        username: 'ama',
        displayName: 'Ama',
        role: 'CASHIER',
        password: 'secret1',
      );
      final service = BackupService(db);
      await service.exportBackup(
        destinationPath: backupPath,
        actingUserId: cashier.id,
      );

      // Data that exists only after the export must not survive the restore.
      await auth.createUser(
        username: 'late',
        displayName: 'Late user',
        role: 'CASHIER',
        password: 'secret2',
      );

      final restartBefore = appRestartCount.value;
      await restoreDatabaseFromBackup(
        db: db,
        currentPath: livePath,
        sourcePath: backupPath,
        actingUsername: kDefaultOwnerUsername,
      );
      expect(appRestartCount.value, restartBefore + 1);

      // The replaced live file contains the backup state, not the later user.
      final restored = await openLive();
      addTearDown(restored.close);
      final users = await restored.select(restored.users).get();
      expect(users.map((u) => u.username), contains('ama'));
      expect(users.map((u) => u.username), isNot(contains('late')));
      // Owner still resolves for the actor on the RESTORE row.
      expect(users.map((u) => u.username), contains(kDefaultOwnerUsername));

      final logs = await restored.select(restored.auditLogs).get();
      expect(
        logs.map((l) => l.action),
        containsAll([AuditAction.backup, AuditAction.restore]),
      );
      final restoreLog = logs.singleWhere(
        (l) => l.action == AuditAction.restore,
      );
      expect(restoreLog.userId, isNotNull);
      expect(restoreLog.details, contains('backup.db'));
    },
  );

  test(
    'restore refuses a backup from a newer app version and keeps data',
    () async {
      final db = await openLive();
      addTearDown(db.close);
      final auth = DriftAuthRepository(db);
      await auth.createUser(
        username: 'ama',
        displayName: 'Ama',
        role: 'CASHIER',
        password: 'secret1',
      );

      // Fabricate a "newer" backup file (a real database at version 99).
      final futureFile = '${temp.path}${Platform.pathSeparator}future.db';
      final probe = sqlite.sqlite3.open(futureFile);
      probe.execute('PRAGMA user_version = 99');
      probe.dispose();

      final restartBefore = appRestartCount.value;
      await expectLater(
        restoreDatabaseFromBackup(
          db: db,
          currentPath: livePath,
          sourcePath: futureFile,
          actingUsername: kDefaultOwnerUsername,
        ),
        throwsA(isA<BackupException>()),
      );
      expect(appRestartCount.value, restartBefore);
      // The live database was not touched.
      final users = await db.select(db.users).get();
      expect(users.map((u) => u.username), contains('ama'));
    },
  );

  test('in-memory databases cannot be exported', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await expectLater(
      BackupService(db)
          .exportBackup(destinationPath: backupPath, actingUserId: 'any'),
      throwsA(isA<BackupException>()),
    );
  });

  test(
    'restore resets the sync cursor so the next pull re-sends host changes',
    () async {
      // A client that had already applied host changes up to rev 500...
      WorkstationConfig.setCurrentForTest(
        const WorkstationConfig(
          mode: 'client',
          stationId: 'station-1',
          stationCode: 'K7F2',
          lastRev: 500,
        ),
      );
      addTearDown(
        () => WorkstationConfig.setCurrentForTest(const WorkstationConfig()),
      );

      final db = await openLive();
      final auth = DriftAuthRepository(db);
      final cashier = await auth.createUser(
        username: 'ama',
        displayName: 'Ama',
        role: 'CASHIER',
        password: 'secret1',
      );
      final service = BackupService(db);
      await service.exportBackup(
        destinationPath: backupPath,
        actingUserId: cashier.id,
      );

      await restoreDatabaseFromBackup(
        db: db,
        currentPath: livePath,
        sourcePath: backupPath,
        actingUsername: kDefaultOwnerUsername,
      );

      // ...restores data from an earlier point. The cursor lives in the
      // workstation config, not in the backup, so the restore has to rewind
      // it: otherwise the next delta pull starts at rev 500 and every host
      // change the backup never received is skipped forever.
      expect(WorkstationConfig.current.lastRev, 0);
    },
  );

  test(
    'a restored database still syncs: role applied and change triggers armed',
    () async {
      WorkstationConfig.setCurrentForTest(
        const WorkstationConfig(
          mode: 'client',
          stationId: 'station-2',
          stationCode: 'ABCD',
          lastRev: 500,
        ),
      );
      addTearDown(
        () => WorkstationConfig.setCurrentForTest(const WorkstationConfig()),
      );

      final db = await openLive();
      final auth = DriftAuthRepository(db);
      final cashier = await auth.createUser(
        username: 'ama',
        displayName: 'Ama',
        role: 'CASHIER',
        password: 'secret1',
      );
      await BackupService(db).exportBackup(
        destinationPath: backupPath,
        actingUserId: cashier.id,
      );

      await restoreDatabaseFromBackup(
        db: db,
        currentPath: livePath,
        sourcePath: backupPath,
        actingUsername: kDefaultOwnerUsername,
      );

      final restored = await openLive();
      addTearDown(restored.close);

      // beforeOpen re-applied this station's role from the config, so the
      // restored file knows it is a client, not a standalone machine.
      final role = await restored
          .customSelect("SELECT value FROM sync_meta WHERE key = 'role'")
          .getSingle();
      expect(role.data['value'], 'client');

      // The sync triggers survived the file swap: a local row takes a fresh
      // change sequence (rev past the column default) and is queued for push.
      await restored.into(restored.categories).insert(
            CategoriesCompanion.insert(
              id: 'c-restored',
              name: 'Post-restore category',
            ),
          );
      final row = await (restored.select(restored.categories)
            ..where((c) => c.id.equals('c-restored')))
          .getSingle();
      expect(row.dirty, isTrue);
      expect(row.rev, greaterThan(1));
    },
  );

  test(
    'restore of a manually copied database keeps rows still in its WAL',
    () async {
      final db = await openLive();
      final auth = DriftAuthRepository(db);
      final cashier = await auth.createUser(
        username: 'ama',
        displayName: 'Ama',
        role: 'CASHIER',
        password: 'secret1',
      );
      await db
          .into(db.categories)
          .insert(CategoriesCompanion.insert(id: 'c-old', name: 'Old category'));

      // A user hand-copies a live database file: the main file plus its WAL,
      // which holds a transaction that was never checkpointed.
      final manualCopy = '${temp.path}${Platform.pathSeparator}manual_copy.db';
      await BackupService(db).exportBackup(
        destinationPath: manualCopy,
        actingUserId: cashier.id,
      );

      final src = sqlite.sqlite3.open(manualCopy);
      src.execute('PRAGMA journal_mode = WAL');
      src.execute(
        "INSERT INTO categories (id, name) VALUES ('c-hot', 'Hot category')",
      );
      // Hold a second connection open on the backup so closing [src] cannot
      // checkpoint the WAL into the main file — that is exactly the state a
      // hand-copied database is in. A connection only counts as a WAL user
      // once it has actually touched the file, hence the SELECT.
      final holder = sqlite.sqlite3.open(manualCopy);
      final holderRows =
          holder.select('SELECT COUNT(*) AS c FROM categories').first['c'];
      expect(holderRows, 15); // 13 seeded + Old category + the one in the WAL
      src.dispose();

      await restoreDatabaseFromBackup(
        db: db,
        currentPath: livePath,
        sourcePath: manualCopy,
        actingUsername: kDefaultOwnerUsername,
      );
      holder.dispose();

      final restored = await openLive();
      addTearDown(restored.close);
      final names = (await restored.select(restored.categories).get())
          .map((c) => c.name);
      expect(names, containsAll(['Old category', 'Hot category']));
    },
  );
}
