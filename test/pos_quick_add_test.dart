import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/domain/product.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';
import 'package:instrument_pos/features/sales/presentation/sales_page.dart';

import 'test_users.dart';

Product product({
  required String id,
  required String name,
  required String sku,
  String? barcode,
  double price = 2500,
}) => Product(
  id: id,
  sku: sku,
  barcode: barcode,
  name: name,
  categoryId: null,
  brandId: null,
  description: null,
  costPrice: 1500,
  sellingPrice: price,
  taxRate: 0,
  reorderLevel: 0,
  trackingType: ProductTrackingType.quantity,
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

/// ProductsRepository with no database behind it — only the till's
/// exact-match lookup is implemented.
class _FakeProductsRepository extends ProductsRepository {
  _FakeProductsRepository(this.products)
    : super(AppDatabase(NativeDatabase.memory()));

  final List<ProductWithStock> products;

  @override
  Future<List<ProductWithStock>> findByExact(
    String query, {
    bool includeInactive = false,
  }) async {
    final lower = query.trim().toLowerCase();
    return [
      for (final item in products)
        if (item.product.name.toLowerCase() == lower ||
            item.product.sku.toLowerCase() == lower ||
            (item.product.barcode?.toLowerCase() == lower))
          item,
    ];
  }
}

void useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> pumpRegister(
  WidgetTester tester, {
  required List<ProductWithStock> catalog,
}) async {
  useDesktopViewport(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(testUser()),
        productsProvider.overrideWith((ref, query) => Stream.value(catalog)),
        productsRepositoryProvider.overrideWithValue(
          _FakeProductsRepository(catalog),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: SalesPage())),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> submitSearch(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  // Let the onChanged rebuild subscribe the query provider before Enter, so
  // the submit handler can read its filtered results.
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  final drumHead = ProductWithStock(
    product: product(
      id: 'p-drum',
      name: 'Drum Head',
      sku: 'DRUM-01',
      barcode: '8991234567890',
    ),
    stock: 5,
  );
  final keyboard = ProductWithStock(
    product: product(
      id: 'p-keys',
      name: 'Keyboard',
      sku: 'KB-100',
      price: 5800,
    ),
    stock: 3,
  );

  group('till quick add', () {
    testWidgets('barcode scan + Enter rings the product up immediately', (
      tester,
    ) async {
      await pumpRegister(tester, catalog: [drumHead, keyboard]);

      expect(
        find.text('Cart is empty.\nTap products to add them.'),
        findsOneWidget,
      );
      // Only the catalog tile shows the price yet.
      expect(find.text('GHS 2500.00'), findsOneWidget);

      // A scanner types the code and presses Enter.
      await submitSearch(tester, '8991234567890');

      // Now also in the cart line.
      expect(find.text('Drum Head'), findsNWidgets(2));
      expect(
        find.text('GHS 2500.00'),
        findsNWidgets(4),
      ); // tile+subtotal+total+remaining
      expect(
        find.text('Cart is empty.\nTap products to add them.'),
        findsNothing,
      );

      // Scan again: quantity goes to 2, totals double.
      await submitSearch(tester, '8991234567890');
      expect(find.text('2'), findsWidgets);
      expect(find.text('GHS 5000.00'), findsNWidgets(3));
    });

    testWidgets('typing the exact name and pressing Enter rings it up', (
      tester,
    ) async {
      await pumpRegister(tester, catalog: [drumHead, keyboard]);
      await submitSearch(tester, 'Drum Head');
      expect(find.text('Drum Head'), findsNWidgets(2));
    });

    testWidgets('unknown input keeps the list and explains itself', (
      tester,
    ) async {
      await pumpRegister(tester, catalog: [drumHead, keyboard]);
      await submitSearch(tester, 'zzz-unknown');
      expect(find.textContaining('No product matches'), findsOneWidget);
      expect(
        find.text('Cart is empty.\nTap products to add them.'),
        findsOneWidget,
      );
    });

    testWidgets('partial single match on the filtered list rings it up', (
      tester,
    ) async {
      // Real app: productsProvider filters to one result for this query.
      await pumpRegister(tester, catalog: [keyboard]);
      await submitSearch(tester, 'Keyb');
      expect(find.text('Keyboard'), findsNWidgets(2));
    });
  });

  group('findByExact', () {
    test('matches barcode, SKU or name exactly and reports stock', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = ProductsRepository(db);
      await repo.upsert(
        product(
          id: 'p1',
          name: 'Drum Head',
          sku: 'DRUM-01',
          barcode: '8991234567890',
        ).toDraft(),
      );
      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion(
              id: Value('m1'),
              productId: Value('p1'),
              movementType: Value(MovementType.openingStock),
              quantity: Value(7),
            ),
          );

      for (final query in ['8991234567890', 'drum-01', 'DRUM HEAD']) {
        final result = await repo.findByExact(query);
        expect(result, hasLength(1), reason: 'query $query');
        expect(result.single.product.id, 'p1');
        expect(result.single.stock, 7);
      }
      // Partial names are not exact matches.
      expect(await repo.findByExact('Drum'), isEmpty);
    });
  });
}

extension on Product {
  ProductDraft toDraft() => ProductDraft(
    id: id,
    name: name,
    sku: sku,
    barcode: barcode,
    sellingPrice: sellingPrice,
    costPrice: costPrice,
  );
}
