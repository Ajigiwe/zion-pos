import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/imports/domain/import_document.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/data/sample_catalog_seeder.dart';
import 'package:instrument_pos/features/products/domain/product.dart';

void main() {
  late AppDatabase db;
  late SampleCatalogSeeder seeder;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    seeder = SampleCatalogSeeder(db);
  });

  tearDown(() => db.close());

  Set<String> uniqueStarterNames() {
    final seen = <String>{};
    return {
      for (final n in kStarterItems)
        if (seen.add(n)) n,
    };
  }

  Future<Map<String, double>> stockByProduct() async {
    final rows = await (db.select(db.products)).get();
    final balances = <String, double>{};
    for (final row in rows) {
      final sum =
          await (db.selectOnly(db.stockMovements)
                ..addColumns([db.stockMovements.quantity.sum()])
                ..where(db.stockMovements.productId.equals(row.id)))
              .getSingle();
      balances[row.name] = sum.read(db.stockMovements.quantity.sum()) ?? 0;
    }
    return balances;
  }

  test(
    'fresh catalog seeds every unique stock-sheet line with stock',
    () async {
      final created = await seeder.seedIfNeeded();

      expect(created, uniqueStarterNames().length);

      final products = await db.select(db.products).get();
      expect(products.map((p) => p.name).toSet(), uniqueStarterNames());

      final balances = await stockByProduct();
      for (final entry in balances.entries) {
        expect(entry.value, 10, reason: '${entry.key} should hold 10 units');
      }

      final marker = await (db.select(
        db.settings,
      )..where((s) => s.key.equals('sampleCatalogSeeded'))).getSingle();
      expect(marker.value, '1');
    },
  );

  test('running twice does not duplicate the catalog', () async {
    await seeder.seedIfNeeded();
    final second = await seeder.seedIfNeeded();

    expect(second, 0);
    expect(
      await db.select(db.products).get(),
      hasLength(uniqueStarterNames().length),
    );
  });

  test('existing products are skipped, not overwritten or restocked', () async {
    // The store already typed in one product before the seeder first ran.
    final repo = ProductsRepository(db);
    await repo.upsert(
      const ProductDraft(
        name: '(01/100 (S)',
        sellingPrice: 999,
        costPrice: 800,
      ),
    );

    final created = await seeder.seedIfNeeded();

    expect(created, uniqueStarterNames().length - 1);
    final kept = await (db.select(
      db.products,
    )..where((p) => p.name.equals('(01/100 (S)'))).getSingle();
    expect(
      kept.sellingPrice,
      999,
      reason: 'existing product must be untouched',
    );

    final balances = await stockByProduct();
    expect(
      balances['(01/100 (S)'],
      0,
      reason: 'existing product keeps its stock',
    );
    expect(balances['12V Battery Rechargeable'], 10);
  });

  test('price list matches the stock sheet exactly', () {
    final priced = {for (final (n, _) in kSampleProductPrices) n};
    expect(priced, uniqueStarterNames());
  });
}
