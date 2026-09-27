import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';
import 'package:instrument_pos/features/settings/data/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SettingsRepository(db);
  });

  tearDown(() => db.close());

  test('first run seeds the store profile rows from kStoreInfo', () async {
    expect(await repo.loadStoreInfo(), kStoreInfo);

    final rows = await db.select(db.settings).get();
    expect(rows, hasLength(3));
    expect(
      rows.map((r) => r.key),
      containsAll([
        StoreSettingKeys.name,
        StoreSettingKeys.address,
        StoreSettingKeys.phone,
      ]),
    );
  });

  test(
    'updateStoreInfo persists the profile and writes an audit entry',
    () async {
      final owner = await db.select(db.users).getSingle();
      const updated = StoreInfo(
        name: 'Zion Music Hub',
        address: 'Tarkwa Market',
        phone: '020 000 0000',
      );

      await repo.updateStoreInfo(updated, actingUserId: owner.id);

      expect(await repo.loadStoreInfo(), updated);

      final audit = (await db.select(db.auditLogs).get())
          .where((log) => log.action == AuditAction.storeDetailsUpdated)
          .toList();
      expect(audit, hasLength(1));
      expect(audit.single.userId, owner.id);
      expect(audit.single.details, contains('Zion Music Hub'));
    },
  );

  test(
    'watchStoreInfo emits the persisted profile, including updates',
    () async {
      expect(await repo.watchStoreInfo().first, kStoreInfo);

      final owner = await db.select(db.users).getSingle();
      final renamed = StoreInfo(
        name: 'Zion Musical Centre (Main)',
        address: kStoreInfo.address,
        phone: kStoreInfo.phone,
      );
      await repo.updateStoreInfo(renamed, actingUserId: owner.id);

      expect(await repo.watchStoreInfo().first, renamed);
    },
  );

  test(
    'low stock threshold defaults to 5 and persists with an audit entry',
    () async {
      expect(await repo.loadLowStockThreshold(), kDefaultLowStockThreshold);

      final owner = await db.select(db.users).getSingle();
      await repo.saveLowStockThreshold(8, actingUserId: owner.id);

      expect(await repo.loadLowStockThreshold(), 8);

      final audit = (await db.select(db.auditLogs).get())
          .where((log) => log.details!.contains('Low stock threshold'))
          .toList();
      expect(audit, hasLength(1));
      expect(audit.single.userId, owner.id);
      expect(audit.single.details, contains('8'));
    },
  );

  test('a malformed stored threshold falls back to the default', () async {
    final owner = await db.select(db.users).getSingle();
    await repo.saveLowStockThreshold(12, actingUserId: owner.id);
    // Corrupt the stored value directly.
    await (db.update(db.settings)
          ..where((s) => s.key.equals(StoreSettingKeys.lowStockThreshold)))
        .write(SettingsCompanion(value: const Value('not-a-number')));
    expect(owner.id, isNotEmpty);

    expect(await repo.loadLowStockThreshold(), kDefaultLowStockThreshold);
  });
}
