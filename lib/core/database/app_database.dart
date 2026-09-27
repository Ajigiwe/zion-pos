import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:instrument_pos/core/database/sync_schema.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/core/database/workstation_config.dart';
import 'package:instrument_pos/core/security/passwords.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:uuid/uuid.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Users,
    Categories,
    Brands,
    Suppliers,
    Products,
    StockMovements,
    Sales,
    SaleItems,
    Payments,
    Refunds,
    RefundItems,
    Exchanges,
    AuditLogs,
    ImportBatches,
    Settings,
    SyncQueue,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Uses the platform file database by default; tests inject an executor.
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'instrument_pos'));

  /// Default categories from the design doc §9, seeded once on first run.
  static const _defaultCategories = [
    'Keyboards',
    'Guitars',
    'Bass Guitars',
    'Drums',
    'Percussion',
    'Microphones',
    'Speakers',
    'Amplifiers',
    'Mixers',
    'Effects',
    'Cables',
    'Accessories',
    'Music Stands',
  ];

  /// Bump whenever the schema changes; backups preflight against this so a
  /// database exported by a newer app version is never restored over an
  /// older one.
  static const int currentSchemaVersion = 8;

  @override
  int get schemaVersion => currentSchemaVersion;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await createSyncMetaTables(m.database);
      await createSyncTriggers(m.database);
      await _seed();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Phase 4: point-of-sale tables.
        await m.createTable(sales);
        await m.createTable(saleItems);
        await m.createTable(payments);
      }
      if (from < 3) {
        // Phase 5: refunds and exchanges.
        await m.createTable(refunds);
        await m.createTable(refundItems);
        await m.createTable(exchanges);
      }
      if (from < 4) {
        // Audit trail (§32).
        await m.createTable(auditLogs);
      }
      if (from < 5) {
        // Phase 6: bulk imports (§20).
        await m.createTable(importBatches);
      }
      if (from < 6) {
        // Editable store profile settings (§…).
        await m.createTable(settings);
      }
      if (from < 7) {
        // Offline-first sync tracking
        await m.addColumn(sales, sales.isSynced);
      }
      if (from < 8) {
        // LAN sync: change sequence + dirty flag on every table, plus the
        // outbox queue and the raw helper tables the sync triggers read.
        await m.addColumn(users, users.rev);
        await m.addColumn(users, users.dirty);
        await m.addColumn(categories, categories.rev);
        await m.addColumn(categories, categories.dirty);
        await m.addColumn(brands, brands.rev);
        await m.addColumn(brands, brands.dirty);
        await m.addColumn(suppliers, suppliers.rev);
        await m.addColumn(suppliers, suppliers.dirty);
        await m.addColumn(products, products.rev);
        await m.addColumn(products, products.dirty);
        await m.addColumn(settings, settings.rev);
        await m.addColumn(settings, settings.dirty);
        await m.addColumn(sales, sales.rev);
        await m.addColumn(sales, sales.dirty);
        await m.addColumn(saleItems, saleItems.rev);
        await m.addColumn(saleItems, saleItems.dirty);
        await m.addColumn(payments, payments.rev);
        await m.addColumn(payments, payments.dirty);
        await m.addColumn(refunds, refunds.rev);
        await m.addColumn(refunds, refunds.dirty);
        await m.addColumn(refundItems, refundItems.rev);
        await m.addColumn(refundItems, refundItems.dirty);
        await m.addColumn(exchanges, exchanges.rev);
        await m.addColumn(exchanges, exchanges.dirty);
        await m.addColumn(stockMovements, stockMovements.rev);
        await m.addColumn(stockMovements, stockMovements.dirty);
        await m.addColumn(auditLogs, auditLogs.rev);
        await m.addColumn(auditLogs, auditLogs.dirty);
        await m.addColumn(importBatches, importBatches.rev);
        await m.addColumn(importBatches, importBatches.dirty);
        await m.createTable(syncQueue);
        await createSyncMetaTables(m.database);
        await createSyncTriggers(m.database);
        await _repairDuplicatedSaleMovements(m.database);
      }
      // Older databases predate the owner seed / settings rows.
      await _ensureDefaultOwner();
      await _ensureStoreSettings();
    },
    beforeOpen: (details) async {
      // The sync triggers update the rows they fire on; SQLite only re-runs
      // triggers recursively when this pragma is on.
      await customStatement('PRAGMA recursive_triggers = OFF');
      await setSyncRole(this, WorkstationConfig.current.mode);
    },
  );

  /// Re-records the station role after the user switches modes at runtime.
  Future<void> updateSyncRole(String mode) => setSyncRole(this, mode);

  /// Repairs stock duplicated by the pre-v8 LAN protocol, which wrote a host
  /// `sync-…` movement next to the client's own movement for the same sale
  /// line. Keeps one copy so `SUM(quantity)` matches reality again.
  Future<void> _repairDuplicatedSaleMovements(DatabaseConnectionUser db) async {
    await db.customStatement(
      "DELETE FROM stock_movements "
      "WHERE id LIKE 'sync-%' AND referenceType = 'sale' AND EXISTS ("
      '  SELECT 1 FROM stock_movements other'
      '  WHERE other.referenceId = stock_movements.referenceId'
      '    AND other.productId = stock_movements.productId'
      '    AND other.id <> stock_movements.id'
      ')',
    );
  }

  Future<void> _seed() async {
    final now = DateTime.now();
    await batch((b) {
      for (final name in _defaultCategories) {
        b.insert(
          categories,
          CategoriesCompanion.insert(
            id: _uuid(),
            name: name,
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    });
    await _ensureDefaultOwner();
    await _ensureStoreSettings();
  }

  /// Inserts the store profile rows (from [kStoreInfo]) when missing.
  Future<void> _ensureStoreSettings() async {
    final existing = await select(settings).get();
    final present = {for (final row in existing) row.key};
    final defaults = [
      (StoreSettingKeys.name, kStoreInfo.name),
      (StoreSettingKeys.address, kStoreInfo.address),
      (StoreSettingKeys.phone, kStoreInfo.phone),
    ];
    final now = DateTime.now();
    await batch((b) {
      for (final (key, value) in defaults) {
        if (!present.contains(key)) {
          b.insert(
            settings,
            SettingsCompanion.insert(
              key: key,
              value: value,
              updatedAt: Value(now),
            ),
          );
        }
      }
    });
  }

  /// Creates the first-run OWNER account when no users exist yet.
  Future<void> _ensureDefaultOwner() async {
    final existing = await (select(users)..limit(1)).get();
    if (existing.isNotEmpty) return;
    await into(users).insert(
      UsersCompanion.insert(
        id: _uuid(),
        username: kDefaultOwnerUsername,
        displayName: 'Owner',
        passwordHash: hashPassword(kDefaultOwnerPassword),
        role: 'OWNER',
      ),
    );
  }

  static String _uuid() => const Uuid().v4();
}
