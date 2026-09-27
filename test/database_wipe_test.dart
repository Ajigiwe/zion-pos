import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/app_restart.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/security/passwords.dart';
import 'package:instrument_pos/features/auth/data/auth_repository.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/domain/product.dart';
import 'package:instrument_pos/features/products/data/sample_catalog_seeder.dart';
import 'package:instrument_pos/features/settings/data/database_backup_service.dart';

void main() {
  late Directory temp;
  late String livePath;
  late String backupPath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pos_wipe_test');
    livePath = '${temp.path}${Platform.pathSeparator}instrument_pos.sqlite';
    backupPath = '${temp.path}${Platform.pathSeparator}pre_wipe_backup.db';
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } on FileSystemException {}
  });

  Future<AppDatabase> openLive() =>
      Future.value(AppDatabase(NativeDatabase(File(livePath))));

  test('wipeDataWithBackup creates mandatory backup and wipes data', () async {
    final db = await openLive();
    addTearDown(db.close);
    final auth = DriftAuthRepository(db);
    final owner = await auth.createUser(
      username: 'owner1',
      displayName: 'Owner One',
      role: 'OWNER',
      password: 'pass',
    );

    final productsRepo = ProductsRepository(db);
    await productsRepo.upsert(
      const ProductDraft(
        name: 'Wipe Test Guitar',
        costPrice: 500,
        sellingPrice: 800,
        taxRate: 0,
        reorderLevel: 2,
        trackingType: ProductTrackingType.quantity,
        isActive: true,
      ),
    );

    final service = BackupService(db);
    final restartBefore = appRestartCount.value;

    await service.wipeDataWithBackup(
      backupDestinationPath: backupPath,
      actingUserId: owner.id,
      actingUsername: owner.username,
    );

    // Verify backup file exists and contains the pre-wipe product
    expect(File(backupPath).existsSync(), isTrue);
    final backupDb = AppDatabase(NativeDatabase(File(backupPath)));
    addTearDown(backupDb.close);
    final backupProducts = await backupDb.select(backupDb.products).get();
    expect(backupProducts.map((p) => p.name), contains('Wipe Test Guitar'));

    // Verify live DB has been wiped clean of products
    final liveProducts = await db.select(db.products).get();
    expect(liveProducts, isEmpty);

    // Verify owner account exists for post-wipe login
    final liveUsers = await db.select(db.users).get();
    expect(liveUsers, isNotEmpty);

    // Verify SampleCatalogSeeder does NOT re-seed sample products after wipe
    final seededCount = await SampleCatalogSeeder(db).seedIfNeeded();
    expect(seededCount, 0);
    final productsAfterSeeder = await db.select(db.products).get();
    expect(productsAfterSeeder, isEmpty);

    expect(appRestartCount.value, restartBefore + 1);
  });
}
