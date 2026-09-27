import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
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

/// Spec for one SQL table name, or null when the table does not sync.
SyncTableSpec? syncSpecFor(String table) {
  for (final spec in syncTables) {
    if (spec.table == table) return spec;
  }
  return null;
}

/// SQL table names that are append-only (pushed idempotently by primary key).
Set<String> syncTxTableNames() => {
  for (final spec in syncTables)
    if (spec.kind == SyncKind.tx) spec.table,
};

/// drift table handles for [syncTables], keyed by [SyncTableSpec.table].
Map<String, TableInfo<Table, DataClass>> syncTableInfos(AppDatabase db) => {
  'users': db.users,
  'categories': db.categories,
  'brands': db.brands,
  'suppliers': db.suppliers,
  'products': db.products,
  'settings': db.settings,
  'sales': db.sales,
  'sale_items': db.saleItems,
  'payments': db.payments,
  'refunds': db.refunds,
  'refund_items': db.refundItems,
  'exchanges': db.exchanges,
  'stock_movements': db.stockMovements,
  'audit_logs': db.auditLogs,
  'import_batches': db.importBatches,
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

/// Indexes the two predicates sync runs constantly: "what has the host
/// changed since my cursor" (pull) and "what do I still owe the host"
/// (outbox flush). Without them both are full table scans.
Future<void> createSyncIndexes(DatabaseConnectionUser db) async {
  for (final spec in syncTables) {
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS "idx_${spec.table}_rev" '
      'ON "${spec.table}"(rev)',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS "idx_${spec.table}_dirty" '
      'ON "${spec.table}"(dirty)',
    );
  }
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
/// Rows written by the sync layer set `rev`/`dirty` explicitly, so the first
/// two triggers never fire for replicated data.
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
      'WHEN NEW.rev = OLD.rev AND OLD.dirty = 0 AND NEW.dirty = 0 '
      'BEGIN '
      '  UPDATE "${spec.table}" SET dirty = 1 WHERE "$pk" = OLD."$pk"; '
      'END;',
    );
    await db.customStatement(
      'CREATE TRIGGER IF NOT EXISTS "trg_${spec.table}_hostrev" '
      'AFTER UPDATE ON "${spec.table}" FOR EACH ROW '
      'WHEN NEW.rev = OLD.rev AND ('
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

String _primaryKeyOf(String table) => syncPrimaryKey(table);

/// Primary-key column of a synced table (`key` for `settings`).
String syncPrimaryKey(String table) => table == 'settings' ? 'key' : 'id';

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

/// Rev and dirty flag of one row, or null when it does not exist.
Future<({int rev, bool dirty})?> readSyncRowMeta(
  DatabaseConnectionUser db,
  String table,
  String entityId,
) async {
  final pk = syncPrimaryKey(table);
  final rows = await db.customSelect(
    'SELECT rev, dirty FROM "$table" WHERE "$pk" = ?',
    variables: [Variable.withString(entityId)],
  ).get();
  if (rows.isEmpty) return null;
  return (
    rev: rows.first.read<int>('rev'),
    dirty: rows.first.read<bool>('dirty'),
  );
}

/// Rows of a synced table matching a raw SQL [where] clause, rebuilt as
/// typed rows so they serialize with the generated `toJson`.
///
/// drift's `customSelect` returns untyped rows, and an erased table handle
/// cannot be filtered with typed column expressions — a raw predicate is the
/// one thing that works for every table. [where] must therefore be built from
/// literals the caller controls (ints, or strings passed through
/// [sqlLiteral]).
Future<List<DataClass>> selectSyncRows(
  DatabaseConnectionUser db,
  TableInfo<Table, DataClass> info, {
  required String where,
  int? limit,
}) async {
  final statement = db.select(info)..where((_) => CustomExpression<bool>(where));
  if (limit != null) statement.limit(limit);
  return statement.get();
}

/// Quotes [value] as a SQL string literal.
String sqlLiteral(String value) => "'${value.replaceAll("'", "''")}'";

/// One row of a synced table in wire format, or null when absent.
Future<Map<String, dynamic>?> readSyncRowJson(
  DatabaseConnectionUser db,
  String table,
  TableInfo<Table, DataClass> info,
  String entityId,
) async {
  final pk = syncPrimaryKey(table);
  final rows = await selectSyncRows(
    db,
    info,
    where: '"$pk" = ${sqlLiteral(entityId)}',
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return rows.first.toJson();
}

/// Writes an incoming wire row into [table], stamping it with [rev] and
/// [dirty] so the sync triggers stay silent. Inserts when the primary key is
/// new, otherwise overwrites every column of the existing row.
///
/// With [replaceOnConflict] a UNIQUE clash (another local row already owns
/// the SKU or username) deletes that row first: the host is the source of
/// truth, so its version wins. The host applies the opposite way — it keeps
/// its own row and hands the clash back to the client as a conflict.
Future<void> writeSyncRow(
  DatabaseConnectionUser db, {
  required String table,
  required TableInfo<Table, DataClass> info,
  required Insertable<DataClass> row,
  required String entityId,
  required int rev,
  required bool dirty,
  bool replaceOnConflict = false,
}) async {
  final pk = syncPrimaryKey(table);
  final columns = <String, Variable>{};
  for (final entry in row.toColumns(false).entries) {
    final value = entry.value;
    if (value is Variable) {
      columns[entry.key] = value;
    }
  }

  final current = await db.customSelect(
    'SELECT rev, dirty FROM "$table" WHERE "$pk" = ?',
    variables: [Variable.withString(entityId)],
  ).get();
  final exists = current.isNotEmpty;
  if (exists) {
    final rowRev = current.first.read<int>('rev');
    final rowDirty = current.first.read<bool>('dirty');
    // The row already carries this revision and is clean — writing it again
    // would look to the edit trigger exactly like a local edit to a synced
    // row, and would re-dirty it forever.
    if (!rowDirty && rev > 0 && rowRev >= rev) return;
    columns['rev'] = Variable<int>(rev > 0 ? rev : rowRev);
  } else {
    columns['rev'] = Variable<int>(rev);
  }
  columns['dirty'] = Variable<bool>(dirty);

  var insertNow = !exists;
  Object? lastError;
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      if (insertNow) {
        final names = columns.keys.map((name) => '"$name"').join(', ');
        final placeholders = List.filled(columns.length, '?').join(', ');
        // Raw SQL rather than `into().insert`: drift's typed insert validates
        // the row against the generated data class, and here the row arrives
        // erased from the wire.
        await db.customUpdate(
          'INSERT INTO "$table" ($names) VALUES ($placeholders)',
          variables: columns.values.toList(),
          updates: {info},
        );
      } else {
        final setClause = columns.keys.map((name) => '"$name" = ?').join(', ');
        await db.customUpdate(
          'UPDATE "$table" SET $setClause WHERE "$pk" = ?',
          variables: [
            ...columns.values,
            Variable<String>(entityId),
          ],
          updates: {info},
        );
      }
      return;
    } catch (e) {
      if (!replaceOnConflict) rethrow;
      lastError = e;
      final column = _uniqueColumn(e);
      final value = column == null ? null : columns[column]?.value;
      if (column == null || value is! String) rethrow;
      final rows = await db.customSelect(
        'SELECT "$pk" AS owner, dirty FROM "$table" WHERE "$column" = ?',
        variables: [Variable.withString(value)],
      ).get();
      if (rows.isEmpty) rethrow;
      final owner = rows.first.read<String?>('owner');
      if (owner == null || owner == entityId) rethrow;
      if (rows.first.read<bool>('dirty')) {
        // The local row still owes the host a change. Overwriting it here
        // would throw that edit away; keep the host row for a later cycle,
        // after the push has resolved the clash.
        debugPrint(
          'sync: keeping dirty local "$table" row $owner, '
          'host $entityId deferred (unique on $column)',
        );
        return;
      }
      debugPrint(
        'sync: replacing local "$table" row $owner (unique on $column) '
        'with the host version',
      );
      await db.customUpdate(
        'DELETE FROM "$table" WHERE "$pk" = ?',
        variables: [Variable.withString(owner)],
        updates: {info},
      );
      insertNow = true;
    }
  }
  throw lastError ?? StateError('writeSyncRow gave up on $table/$entityId');
}

/// Column name SQLite reported in a UNIQUE violation, when it can tell us.
String? _uniqueColumn(Object error) => RegExp(
  r'UNIQUE constraint failed:\s*[\w]+\.(?<column>\w+)',
).firstMatch('$error')?.namedGroup('column');
