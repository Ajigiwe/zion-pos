import 'package:drift/drift.dart';
import 'package:instrument_pos/core/database/app_database.dart';

/// How a table participates in LAN sync.
enum SyncKind {
  /// Catalog rows (products, users, settings…): editable on any station and
  /// conflict-checked against the host revision.
  catalog,

  /// Transaction rows (sales, refunds, movements…): append-only and
  /// idempotent — the host accepts a row once, keyed by primary key.
  tx,
}

/// One table that travels over the wire, shared by the client sync service
/// and the host server so both sides always agree on what is synced.
class SyncTableSpec {
  const SyncTableSpec(this.table, {this.fromJson, this.kind = SyncKind.tx});

  /// SQL table name as created by drift.
  final String table;

  /// Rebuilds a typed row from a wire payload. Null for tables that are not
  /// pushed by clients (they are pull-only).
  final Insertable<DataClass>? Function(Map<String, dynamic> json)? fromJson;

  final SyncKind kind;

  bool get isCatalog => kind == SyncKind.catalog;
}

/// Every table that participates in delta sync, in parent-before-child order.
const syncTables = <SyncTableSpec>[
  SyncTableSpec('users', kind: SyncKind.catalog, fromJson: _users),
  SyncTableSpec('categories', kind: SyncKind.catalog, fromJson: _categories),
  SyncTableSpec('brands', kind: SyncKind.catalog, fromJson: _brands),
  SyncTableSpec('suppliers', kind: SyncKind.catalog, fromJson: _suppliers),
  SyncTableSpec('products', kind: SyncKind.catalog, fromJson: _products),
  SyncTableSpec('settings', kind: SyncKind.catalog, fromJson: _settings),
  SyncTableSpec('sales', fromJson: _sales),
  SyncTableSpec('sale_items', fromJson: _saleItems),
  SyncTableSpec('payments', fromJson: _payments),
  SyncTableSpec('refunds', fromJson: _refunds),
  SyncTableSpec('refund_items', fromJson: _refundItems),
  SyncTableSpec('exchanges', fromJson: _exchanges),
  SyncTableSpec('stock_movements', fromJson: _stockMovements),
  SyncTableSpec('audit_logs', fromJson: _auditLogs),
  SyncTableSpec('import_batches', fromJson: _importBatches),
];

// Tear-offs of the generated row factories. They keep the table list above
// const while still letting the sync layer rebuild typed rows.
Insertable<DataClass> _users(Map<String, dynamic> j) => User.fromJson(j);
Insertable<DataClass> _categories(Map<String, dynamic> j) =>
    Category.fromJson(j);
Insertable<DataClass> _brands(Map<String, dynamic> j) => Brand.fromJson(j);
Insertable<DataClass> _suppliers(Map<String, dynamic> j) =>
    Supplier.fromJson(j);
Insertable<DataClass> _products(Map<String, dynamic> j) => Product.fromJson(j);
Insertable<DataClass> _settings(Map<String, dynamic> j) => Setting.fromJson(j);
Insertable<DataClass> _sales(Map<String, dynamic> j) => Sale.fromJson(j);
Insertable<DataClass> _saleItems(Map<String, dynamic> j) =>
    SaleItem.fromJson(j);
Insertable<DataClass> _payments(Map<String, dynamic> j) => Payment.fromJson(j);
Insertable<DataClass> _refunds(Map<String, dynamic> j) => Refund.fromJson(j);
Insertable<DataClass> _refundItems(Map<String, dynamic> j) =>
    RefundItem.fromJson(j);
Insertable<DataClass> _exchanges(Map<String, dynamic> j) =>
    Exchange.fromJson(j);
Insertable<DataClass> _stockMovements(Map<String, dynamic> j) =>
    StockMovement.fromJson(j);
Insertable<DataClass> _auditLogs(Map<String, dynamic> j) =>
    AuditLog.fromJson(j);
Insertable<DataClass> _importBatches(Map<String, dynamic> j) =>
    ImportBatch.fromJson(j);

/// drift table handles for the tables above, keyed by [SyncTableSpec.table].
Map<String, TableInfo<Table, DataClass>> syncTableInfos(AppDatabase db) => {
  'users': db.users,
  'categories': db.categories,
  'brands': db.brands,
  'suppliers': db.suppliers,
  'products': db.products,
  'settings': db.settings,
  'sales': db.sales,
  'saleItems': db.saleItems,
  'payments': db.payments,
  'refunds': db.refunds,
  'refundItems': db.refundItems,
  'exchanges': db.exchanges,
  'stockMovements': db.stockMovements,
  'auditLogs': db.auditLogs,
  'importBatches': db.importBatches,
};

/// Settings keys that belong to the store and therefore follow the host.
/// Machine-local keys (printer.*, network.*, theme_*) never sync.
bool isSharedSettingKey(String key) =>
    key.startsWith('store.') ||
    key.startsWith('receipt.') ||
    key == 'inventory.lowStockThreshold';

/// Raw helper tables drift does not model: the change-sequence counter and
/// the station role read by the sync triggers.
Future<void> createSyncMetaTables(DatabaseConnectionUser db) async {
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS sync_counter ('
    'id INTEGER PRIMARY KEY CHECK (id = 1), '
    'value INTEGER NOT NULL)',
  );
  await db.customStatement(
    "INSERT OR REPLACE INTO sync_counter (id, value) VALUES (1, 1)",
  );
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS sync_meta ('
    'key TEXT PRIMARY KEY, '
    'value TEXT NOT NULL)',
  );
  await db.customStatement(
    "INSERT OR REPLACE INTO sync_meta (key, value) VALUES ('role', 'standalone')",
  );
}

/// Creates the triggers that keep `rev`/`dirty` honest without every
/// repository remembering to maintain them:
///
/// * a locally created row (dirty = 1) takes the next change sequence, so a
///   host edit is visible to clients through `rev > lastSeen`;
/// * a local edit marks the row dirty so it is pushed;
/// * on a host/standalone station a local edit also takes a new sequence,
///   which is what tells every client the row changed.
///
/// Rows written by the sync layer set `rev`/`dirty` explicitly, so none of
/// these triggers fire for replicated data.
Future<void> createSyncTriggers(DatabaseConnectionUser db) async {
  for (final spec in syncTables) {
    final pk = _primaryKeyOf(spec.table);
    await db.customStatement(
      'CREATE TRIGGER IF NOT EXISTS "trg_${spec.table}_insert" '
      'AFTER INSERT ON "${spec.table}" FOR EACH ROW WHEN NEW.dirty = 1 '
      'BEGIN '
      '  UPDATE sync_counter SET value = value + 1; '
      '  UPDATE "${spec.table}" SET rev = (SELECT value FROM sync_counter) '
      '    WHERE "$pk" = NEW."$pk"; '
      'END;',
    );
    await db.customStatement(
      'CREATE TRIGGER IF NOT EXISTS "trg_${spec.table}_edit" '
      'AFTER UPDATE ON "${spec.table}" FOR EACH ROW '
      'WHEN NEW.rev = OLD.rev AND NEW.dirty = 0 '
      'BEGIN '
      '  UPDATE "${spec.table}" SET dirty = 1 WHERE "$pk" = OLD."$pk"; '
      'END;',
    );
    await db.customStatement(
      'CREATE TRIGGER IF NOT EXISTS "trg_${spec.table}_hostrev" '
      'AFTER UPDATE ON "${spec.table}" FOR EACH ROW '
      'WHEN NEW.rev = OLD.rev AND NEW.dirty = 0 AND ('
      '  SELECT COALESCE(value, \'standalone\') FROM sync_meta '
      "  WHERE key = 'role') IN ('host', 'standalone') "
      'BEGIN '
      '  UPDATE sync_counter SET value = value + 1; '
      '  UPDATE "${spec.table}" SET rev = (SELECT value FROM sync_counter) '
      '    WHERE "$pk" = OLD."$pk"; '
      'END;',
    );
  }
}

String _primaryKeyOf(String table) => table == 'settings' ? 'key' : 'id';

/// Records which role this database is playing. Triggers read it to decide
/// whether local edits advance the change sequence.
Future<void> setSyncRole(DatabaseConnectionUser db, String mode) async {
  await db.customStatement(
    "INSERT OR REPLACE INTO sync_meta (key, value) VALUES ('role', ?)",
    [mode],
  );
}

/// The next global change sequence. Callers must run this inside the same
/// transaction as the write it labels.
Future<int> nextRev(DatabaseConnectionUser db) async {
  await db.customStatement('UPDATE sync_counter SET value = value + 1');
  final row = await db.customSelect('SELECT value FROM sync_counter').getSingle();
  return row.data['value'] as int;
}

/// The highest change sequence a host has issued so far.
Future<int> currentRev(DatabaseConnectionUser db) async {
  final row = await db.customSelect('SELECT value FROM sync_counter').getSingle();
  return row.data['value'] as int;
}
