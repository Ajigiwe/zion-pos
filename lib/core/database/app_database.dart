import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:instrument_pos/core/database/tables.dart';
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
  static const int currentSchemaVersion = 7;

  @override
  int get schemaVersion => currentSchemaVersion;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
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
      // Older databases predate the owner seed / settings rows.
      await _ensureDefaultOwner();
      await _ensureStoreSettings();
    },
  );

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
