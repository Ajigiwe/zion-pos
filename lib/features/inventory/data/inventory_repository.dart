import 'package:drift/drift.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';
import 'package:uuid/uuid.dart';

class MovementWithProduct {
  const MovementWithProduct({required this.movement, required this.product});

  final StockMovement movement;
  final Product product;
}

class MovementFilter {
  const MovementFilter({this.type, this.search = ''});

  final MovementType? type;
  final String search;

  @override
  bool operator ==(Object other) =>
      other is MovementFilter && other.type == type && other.search == search;

  @override
  int get hashCode => Object.hash(type, search);
}

class InventoryRepository {
  InventoryRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Reactive ledger feed: every movement joined with its product,
  /// newest first, optionally filtered by type and product search.
  Stream<List<MovementWithProduct>> watchMovements(MovementFilter filter) {
    final query = _db.select(_db.stockMovements).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.stockMovements.productId),
      ),
    ])..orderBy([OrderingTerm.desc(_db.stockMovements.createdAt)]);

    final type = filter.type;
    if (type != null) {
      query.where(_db.stockMovements.movementType.equalsValue(type));
    }
    final search = filter.search.trim().toLowerCase();
    if (search.isNotEmpty) {
      final pattern = '%$search%';
      query.where(
        _db.products.name.lower().like(pattern) |
            _db.products.sku.lower().like(pattern),
      );
    }

    return query.watch().map(
      (rows) => [
        for (final row in rows)
          MovementWithProduct(
            movement: row.readTable(_db.stockMovements),
            product: row.readTable(_db.products),
          ),
      ],
    );
  }

  /// Current stock of one product: SUM of its ledger movements (§2.3).
  Future<double> stockBalanceOf(String productId) async {
    final query = _db.selectOnly(_db.stockMovements)
      ..addColumns([_db.stockMovements.quantity.sum()])
      ..where(_db.stockMovements.productId.equals(productId));
    final row = await query.getSingle();
    return row.read(_db.stockMovements.quantity.sum()) ?? 0;
  }

  /// Appends one signed movement to the ledger.
  ///
  /// [quantity] carries the ledger sign convention: purchases/returns are
  /// positive, sales/damage/transfers-out negative (§13). [userId] records who
  /// performed the action for the audit trail (§32).
  Future<void> recordMovement({
    required String productId,
    required MovementType type,
    required double quantity,
    String? reason,
    String? referenceType,
    String? referenceId,
    String? userId,
  }) async {
    if (quantity == 0) {
      throw ArgumentError('A stock movement must have a non-zero quantity.');
    }
    await _db
        .into(_db.stockMovements)
        .insert(
          StockMovementsCompanion(
            id: Value(_uuid.v4()),
            productId: Value(productId),
            movementType: Value(type),
            quantity: Value(quantity),
            referenceType: Value<String?>(referenceType),
            referenceId: Value<String?>(referenceId),
            userId: Value<String?>(userId),
            reason: Value<String?>(reason),
            createdAt: Value(DateTime.now()),
          ),
        );
    await AuditRepository(_db).log(
      action: type == MovementType.adjustment
          ? AuditAction.stockAdjustment
          : type.name.toUpperCase(),
      userId: userId,
      entityType: 'product',
      entityId: productId,
      details: '${type.name.toUpperCase()} ${_signed(quantity)}',
    );
  }

  static String _signed(double quantity) =>
      quantity >= 0 ? '+${_trim(quantity)}' : _trim(quantity).toString();

  static String _trim(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  /// Creates OPENING_STOCK movements for every product with a quantity > 0,
  /// atomically in one transaction (§21, §39).
  Future<int> recordOpeningStock(
    Map<String, int> quantities, {
    String? userId,
  }) async {
    final entries = {
      for (final entry in quantities.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    if (entries.isEmpty) return 0;
    await _db.transaction(() async {
      for (final entry in entries.entries) {
        await _db
            .into(_db.stockMovements)
            .insert(
              StockMovementsCompanion(
                id: Value(_uuid.v4()),
                productId: Value(entry.key),
                movementType: Value(MovementType.openingStock),
                quantity: Value(entry.value.toDouble()),
                reason: const Value<String?>('Opening stock'),
                userId: Value<String?>(userId),
                createdAt: Value(DateTime.now()),
              ),
            );
      }
    });
    if (entries.isNotEmpty) {
      final units = entries.values.fold<int>(0, (sum, qty) => sum + qty);
      await AuditRepository(_db).log(
        action: AuditAction.openingStock,
        userId: userId,
        entityType: 'import',
        details: '${entries.length} products, $units units',
      );
    }
    return entries.length;
  }
}
