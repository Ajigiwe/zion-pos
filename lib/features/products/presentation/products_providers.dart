import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/data/sample_catalog_seeder.dart';

final productsRepositoryProvider = Provider<ProductsRepository>((ref) {
  return ProductsRepository(ref.watch(databaseProvider));
});

/// Debug-only one-time seeding of sample products from the store's stock sheet.
final sampleCatalogSeederProvider = Provider<SampleCatalogSeeder>((ref) {
  return SampleCatalogSeeder(ref.watch(databaseProvider));
});

/// Product listing with live search; watch this anywhere the UI needs stock.
final productsProvider = StreamProvider.autoDispose
    .family<List<ProductWithStock>, String>((ref, query) {
      return ref.watch(productsRepositoryProvider).watchProducts(query: query);
    });

/// Single product by id for the edit form.
final productProvider = FutureProvider.autoDispose.family<Product?, String>((
  ref,
  id,
) {
  return ref.watch(productsRepositoryProvider).getById(id);
});

/// Categories for dropdowns, seeded on first run (§9).
final categoriesProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.categories)
    ..orderBy([(t) => OrderingTerm.asc(t.name)]);
  return query.watch();
});

final brandsProvider = StreamProvider<List<Brand>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.brands)
    ..orderBy([(t) => OrderingTerm.asc(t.name)]);
  return query.watch();
});
