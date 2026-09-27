import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/domain/product.dart';
import 'package:instrument_pos/features/products/presentation/products_page.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';

Product _makeProduct(String id, String name, String sku, double price) {
  final now = DateTime.now();
  return Product(
    id: id,
    name: name,
    sku: sku,
    costPrice: price * 0.7,
    sellingPrice: price,
    taxRate: 0,
    reorderLevel: 5,
    trackingType: ProductTrackingType.quantity,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    rev: 1, dirty: false,
  );
}

void main() {
  testWidgets('ProductsPage displays products table with action buttons', (tester) async {
    final p1 = _makeProduct('p1', 'Yamaha Keyboard', 'YAM-001', 1200);
    final products = [
      ProductWithStock(product: p1, stock: 10),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productsProvider.overrideWith((ref, query) => Stream.value(products)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ProductsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify row items
    expect(find.text('Yamaha Keyboard'), findsOneWidget);
    expect(find.text('GHS 1200'), findsOneWidget);

    // Verify action buttons exist
    expect(find.byTooltip('View details'), findsOneWidget);
    expect(find.byTooltip('Edit product'), findsOneWidget);
    expect(find.byTooltip('Delete product'), findsOneWidget);

    // Tap View Details button
    await tester.tap(find.byTooltip('View details'));
    await tester.pumpAndSettle();

    // Verify dialog opens
    expect(find.text('Yamaha Keyboard'), findsNWidgets(2)); // Table row + Dialog title
    expect(find.text('Selling Price'), findsOneWidget);
    expect(find.text('Cost Price'), findsOneWidget);
    expect(find.text('Stock Level'), findsOneWidget);

    // Close detail dialog
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });
}
