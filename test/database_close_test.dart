import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/app_restart.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/security/passwords.dart';
import 'package:instrument_pos/features/auth/data/auth_repository.dart';
import 'package:instrument_pos/features/settings/data/database_backup_service.dart';

/// Regression tests for "restore is stuck loading".
///
/// Riverpod pauses the drift `watch()` stream of a consumer whose TickerMode
/// is off, and drift's `DatabaseConnectionUser.close()` waits for every
/// watch() listener to receive its close event — which a paused listener
/// never does. The restore path awaited `db.close()`, so the spinner after
/// the file dialog never stopped.
void main() {
  late Directory temp;
  late String livePath;
  late String backupPath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pos_close_test');
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

  Future<User> seededUser(AppDatabase db) {
    return DriftAuthRepository(db).createUser(
      username: 'ama',
      displayName: 'Ama',
      role: 'CASHIER',
      password: 'secret1',
    );
  }

  test('close() completes while watch() subscriptions are live', () async {
    final db = await openLive();
    addTearDown(() => db.close().ignore());
    await seededUser(db);

    final sub1 = db.select(db.categories).watch().listen((_) {});
    final sub2 = db.select(db.auditLogs).watch().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await db.close().timeout(const Duration(seconds: 8));
    await sub1.cancel();
    await sub2.cancel();
  });

  test('close() completes while a watch() subscription is paused', () async {
    final db = await openLive();
    addTearDown(() => db.close().ignore());
    await seededUser(db);

    final sub = db.select(db.categories).watch().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // What Riverpod does to a consumer whose TickerMode is off.
    sub.pause();

    await db.close().timeout(const Duration(seconds: 8));
    await sub.cancel();
  });

  test('export + restore complete while a watch() subscription is paused',
      () async {
    final db = await openLive();
    final user = await seededUser(db);

    await BackupService(db).exportBackup(
      destinationPath: backupPath,
      actingUserId: user.id,
    );

    final sub = db.select(db.users).watch().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    sub.pause();

    final restartBefore = appRestartCount.value;
    await restoreDatabaseFromBackup(
      db: db,
      currentPath: livePath,
      sourcePath: backupPath,
      actingUsername: kDefaultOwnerUsername,
    ).timeout(const Duration(seconds: 20));
    await sub.cancel();
    expect(appRestartCount.value, restartBefore + 1);

    // The swap really happened: the restored file opens with the backup's data.
    final restored = await openLive();
    addTearDown(() => restored.close().ignore());
    final users = await restored.select(restored.users).get();
    expect(users.map((u) => u.username), contains('ama'));
  });

  testWidgets(
    'restore finishes while a TickerMode-off consumer watches the database',
    (tester) async {
      // Seed + export are real file I/O: they must run outside the fake-async
      // zone the widget-test binding uses.
      final db = await tester.runAsync(() async {
        final db = await openLive();
        final user = await seededUser(db);
        await BackupService(db).exportBackup(
          destinationPath: backupPath,
          actingUserId: user.id,
        );
        return db;
      }) ?? fail('setup did not run');
      addTearDown(() => db.close().ignore());

      final categoriesProvider = StreamProvider.autoDispose(
        (ref) => db.select(db.categories).watch(),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TickerMode(
              // TickerMode off is what pauses a consumer's provider
              // subscriptions in the app (an inactive page or route).
              enabled: false,
              child: Consumer(
                builder: (context, ref, _) {
                  ref.watch(categoriesProvider);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final restartBefore = appRestartCount.value;
      await tester.runAsync(
        () => restoreDatabaseFromBackup(
              db: db,
              currentPath: livePath,
              sourcePath: backupPath,
              actingUsername: kDefaultOwnerUsername,
            ).timeout(const Duration(seconds: 15)),
      );
      expect(appRestartCount.value, restartBefore + 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
