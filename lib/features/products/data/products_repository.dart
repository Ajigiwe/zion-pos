import 'package:drift/drift.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/products/domain/product.dart';
import 'package:uuid/uuid.dart';

/// Product plus its current stock, derived from the movement ledger (§2.3).
class ProductWithStock {
  const ProductWithStock({required this.product, required this.stock});

  final Product product;
  final double stock;
}

class ProductsRepository {
  ProductsRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Watching products with an optional search on name/SKU/barcode,
  /// enriched with the current stock balance from the ledger.
  /// Watching products with an optional search on name/SKU/barcode,
  /// enriched with the current stock balance from the ledger.
  Stream<List<ProductWithStock>> watchProducts({
    String query = '',
    bool? includeInactive,
  }) {
    final search = query.trim().toLowerCase();
    final productsQuery = _db.select(_db.products)
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    if (includeInactive == false) {
      productsQuery.where((p) => p.isActive.equals(true));
    }
    if (search.isNotEmpty) {
      final pattern = '%$search%';
      productsQuery.where((p) {
        final like = p.name.lower().like(pattern) | p.sku.lower().like(pattern);
        final barcodeLike =
            p.barcode.isNotNull() & p.barcode.lower().like(pattern);
        return like | barcodeLike;
      });
    }

    return productsQuery.watch().asyncMap((rows) async {
      final balances = await _stockBalances();
      return [
        for (final row in rows)
          ProductWithStock(product: row, stock: balances[row.id] ?? 0),
      ];
    });
  }

  /// Sum of all ledger movements per product — the authoritative stock value.
  Future<Map<String, double>> _stockBalances() async {
    final query = _db.selectOnly(_db.stockMovements)
      ..addColumns([
        _db.stockMovements.productId,
        _db.stockMovements.quantity.sum(),
      ])
      ..groupBy([_db.stockMovements.productId]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(_db.stockMovements.productId)!:
            row.read(_db.stockMovements.quantity.sum()) ?? 0,
    };
  }

  Future<Product?> getById(String id) => (_db.select(
    _db.products,
  )..where((p) => p.id.equals(id))).getSingleOrNull();

  /// Products whose barcode, SKU or name equals [query] exactly
  /// (case-insensitive), with current stock — the till's "scan and ring up"
  /// path. Unlike [watchProducts] this ignores partial matches, so a scanner
  /// hitting Enter never rings up the wrong product.
  Future<List<ProductWithStock>> findByExact(
    String query, {
    bool includeInactive = false,
  }) async {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return const [];
    final rows = await (_db.select(_db.products)..where(
          (p) =>
              (includeInactive ? const Constant(true) : p.isActive.equals(true)) &
              (p.name.lower().equals(lower) |
                  p.sku.lower().equals(lower) |
                  (p.barcode.isNotNull() & p.barcode.lower().equals(lower))),
        ))
        .get();
    if (rows.isEmpty) return const [];
    final balances = await _stockBalances();
    return [
      for (final row in rows)
        ProductWithStock(product: row, stock: balances[row.id] ?? 0),
    ];
  }

  Future<void> upsert(ProductDraft draft) async {
    final now = DateTime.now();
    final id = draft.id ?? _uuid.v4();
    final existing = draft.id == null ? null : await getById(id);
    await _db
        .into(_db.products)
        .insert(
          ProductsCompanion(
            id: Value(id),
            sku: Value(draft.sku ?? _deriveSku(draft.name)),
            barcode: Value(draft.barcode),
            name: Value(draft.name),
            categoryId: Value(draft.categoryId),
            brandId: Value(draft.brandId),
            description: Value(draft.description),
            costPrice: Value(draft.costPrice),
            sellingPrice: Value(draft.sellingPrice),
            taxRate: Value(draft.taxRate),
            reorderLevel: Value(draft.reorderLevel),
            trackingType: Value(draft.trackingType),
            isActive: Value(draft.isActive),
            createdAt: Value(existing?.createdAt ?? now),
            updatedAt: Value(now),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Soft delete — products referenced by history are never removed (§32).
  Future<void> setActive(String id, {required bool active}) async {
    await (_db.update(_db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        isActive: Value(active),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Checks whether a product has zero sales or refund history and can be permanently deleted.
  Future<bool> canHardDelete(String productId) async {
    final saleItemCount = await (_db.selectOnly(_db.saleItems)
          ..addColumns([_db.saleItems.id.count()])
          ..where(_db.saleItems.productId.equals(productId)))
        .getSingle();
    if ((saleItemCount.read(_db.saleItems.id.count()) ?? 0) > 0) return false;

    final refundCount = await (_db.selectOnly(_db.refundItems)
          ..addColumns([_db.refundItems.id.count()])
          ..where(_db.refundItems.productId.equals(productId)))
        .getSingle();
    if ((refundCount.read(_db.refundItems.id.count()) ?? 0) > 0) return false;

    return true;
  }

  /// Deletes a product if it has no sales or refund history (cleaning up any stock movements);
  /// deactivates it otherwise to keep historical accounting accurate (§32).
  /// Returns `true` if permanently deleted, `false` if soft-deleted (deactivated).
  Future<bool> deleteProduct(String id) async {
    final removable = await canHardDelete(id);
    if (removable) {
      return await _db.transaction(() async {
        await (_db.delete(_db.stockMovements)..where((m) => m.productId.equals(id))).go();
        final count = await (_db.delete(_db.products)..where((p) => p.id.equals(id))).go();
        return count > 0;
      });
    } else {
      await setActive(id, active: false);
      return false;
    }
  }

  static String _deriveSku(String name) {
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return '${slug.substring(0, slug.length.clamp(1, 16))}-${_uuid.v4().substring(0, 6)}'
        .toUpperCase();
  }
}
