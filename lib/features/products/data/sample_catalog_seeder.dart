import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/imports/domain/import_document.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/domain/product.dart';
import 'package:uuid/uuid.dart';

/// Selling price (GHS) for each line of the store's stock sheet. These are
/// placeholder *test* values — the client's sheet has no prices yet — and are
/// meant to be edited in the app before real use.
const List<(String, double)> kSampleProductPrices = [
  ('(01/100 (S)', 60),
  ('10\u201D Evans Double Velum', 280),
  ('10\u201D GLS Naked Speaker', 320),
  ('10\u201D Naked Speaker', 270),
  ('10\u201D Olympic Single', 180),
  ('11\u201D Olympic Double', 220),
  ('11\u201D Premier Single', 200),
  ('12\u201D Channel Mixer Amp', 1450),
  ('12\u201D Channel Mixer', 980),
  ('12\u201D Evans Double Velum', 330),
  ('12\u201D GLS Double Velum', 340),
  ('12\u201D Single Velum', 150),
  ('12\u201D GLS Naked Speaker', 420),
  ('12\u201D Naked Speaker', 370),
  ('12\u201D Remo Double Velum', 350),
  ('12V Battery Rechargeable', 290),
];

/// One-time, debug-only seeding of the store's stock sheet as sample products
/// with opening stock, so the POS/catalog can be exercised before real data
/// arrives. Runs at startup (never in release builds) and marks itself done in
/// the `settings` table, so it cannot run twice or resurrect deleted rows.
class SampleCatalogSeeder {
  SampleCatalogSeeder(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const _markerKey = 'sampleCatalogSeeded';
  static const double _openingQty = 10;

  /// Creates the products missing from the catalog (each with 10 units of
  /// opening stock) and records that seeding ran. Returns how many products
  /// were created.
  Future<int> seedIfNeeded() async {
    if (!kDebugMode) return 0;
    final marker = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(_markerKey))).getSingleOrNull();
    if (marker?.value == '1') return 0;

    // The sheet lists 18 lines; duplicated lines collapse into one product
    // each, matching how an import would behave for a product catalog.
    final uniqueNames = <String>[];
    final seen = <String>{};
    for (final item in kStarterItems) {
      if (seen.add(item)) uniqueNames.add(item);
    }

    final existingNames =
        (await (_db.selectOnly(
              _db.products,
            )..addColumns([_db.products.name])).get())
            .map((r) => r.read(_db.products.name)!)
            .toSet();
    final priceBy = {
      for (final (name, price) in kSampleProductPrices) name: price,
    };
    var created = 0;

    await _db.transaction(() async {
      final repo = ProductsRepository(_db);
      final present = existingNames;
      final now = DateTime.now();
      for (final name in uniqueNames) {
        if (present.contains(name)) continue; // never touch existing products
        final price = priceBy[name] ?? 100;
        await repo.upsert(
          ProductDraft(
            name: name,
            sellingPrice: price,
            costPrice: (price * 0.7).roundToDouble(),
            reorderLevel: 5,
          ),
        );
        final row = await (_db.select(
          _db.products,
        )..where((p) => p.name.equals(name))).getSingle();
        await _db
            .into(_db.stockMovements)
            .insert(
              StockMovementsCompanion(
                id: Value(_uuid.v4()),
                productId: Value(row.id),
                movementType: Value(MovementType.openingStock),
                quantity: Value(_openingQty),
                reason: Value<String?>('Sample catalog (test data)'),
                createdAt: Value(now),
              ),
            );
        created++;
      }
      await (_db.into(_db.settings)).insertOnConflictUpdate(
        SettingsCompanion(
          key: Value(_markerKey),
          value: Value('1'),
          updatedAt: Value(now),
        ),
      );
    });
    return created;
  }
}
