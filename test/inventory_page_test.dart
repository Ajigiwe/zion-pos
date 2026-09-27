import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/inventory/data/inventory_repository.dart';
import 'package:instrument_pos/features/inventory/presentation/inventory_page.dart';
import 'package:instrument_pos/features/inventory/presentation/inventory_providers.dart';
import 'package:instrument_pos/features/inventory/presentation/opening_stock_wizard_page.dart';
import 'package:instrument_pos/features/inventory/presentation/stock_sheet_service.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';

import 'test_users.dart';

Product sampleProduct() => Product(
  id: 'p1',
  sku: 'YAM-PSR-E473',
  barcode: null,
  name: 'Yamaha PSR-E473',
  categoryId: null,
  brandId: null,
  description: null,
  costPrice: 4500,
  sellingPrice: 5800,
  taxRate: 0,
  reorderLevel: 0,
  trackingType: ProductTrackingType.quantity,
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  rev: 1, dirty: false,
);

void useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget wrap(Widget child, dynamic overrides) => ProviderScope(
  overrides: [
    // Inventory actions are permission-gated; run tests as the owner.
    currentUserProvider.overrideWithValue(testUser()), ...overrides as Iterable,
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  testWidgets(
    'ledger renders movements with product, type and signed quantity',
    (tester) async {
      useDesktopViewport(tester);
      final product = sampleProduct();
      await tester.pumpWidget(
        wrap(const InventoryPage(), [
          productsProvider.overrideWith(
            (ref, query) =>
                Stream.value([ProductWithStock(product: product, stock: 10)]),
          ),
          movementsProvider.overrideWith(
            (ref, filter) => Stream.value([
              MovementWithProduct(
                movement: StockMovement(
                  id: 'm1',
                  productId: product.id,
                  movementType: MovementType.openingStock,
                  quantity: 10,
                  reason: 'Opening stock',
                  createdAt: DateTime(2026, 1, 1, 9, 30),
                  rev: 1, dirty: false,
                ),
                product: product,
              ),
            ]),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Yamaha PSR-E473'), findsOneWidget);
      expect(find.text('+10'), findsOneWidget);
      expect(find.text('2026-01-01 09:30'), findsOneWidget);
      expect(find.text('Add stock'), findsOneWidget);
      expect(find.text('Adjust'), findsOneWidget);
      expect(find.text('Damage'), findsOneWidget);
    },
  );

  testWidgets('ledger shows empty state when there are no movements', (
    tester,
  ) async {
    useDesktopViewport(tester);
    final product = sampleProduct();
    await tester.pumpWidget(
      wrap(const InventoryPage(), [
        productsProvider.overrideWith(
          (ref, query) =>
              Stream.value([ProductWithStock(product: product, stock: 0)]),
        ),
        movementsProvider.overrideWith(
          (ref, filter) => Stream.value(const <MovementWithProduct>[]),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('No stock movements yet'), findsOneWidget);
  });

  testWidgets('add-stock dialog opens with product picker', (tester) async {
    useDesktopViewport(tester);
    final product = sampleProduct();
    await tester.pumpWidget(
      wrap(const InventoryPage(), [
        productsProvider.overrideWith(
          (ref, query) =>
              Stream.value([ProductWithStock(product: product, stock: 5)]),
        ),
        movementsProvider.overrideWith(
          (ref, filter) => Stream.value(const <MovementWithProduct>[]),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add stock'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Units received'), findsOneWidget);
    expect(find.text('Select a product'), findsOneWidget);
    expect(find.text('Record movement'), findsOneWidget);
  });

  testWidgets(
    'opening stock wizard offers quantities for zero-stock products',
    (tester) async {
      useDesktopViewport(tester);
      final product = sampleProduct();
      await tester.pumpWidget(
        wrap(const OpeningStockWizardPage(), [
          productsProvider.overrideWith(
            (ref, query) =>
                Stream.value([ProductWithStock(product: product, stock: 0)]),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Yamaha PSR-E473'), findsOneWidget);
      expect(find.text('Record opening stock'), findsOneWidget);
    },
  );

  testWidgets('opening stock wizard reports when nothing needs opening stock', (
    tester,
  ) async {
    useDesktopViewport(tester);
    final product = sampleProduct();
    await tester.pumpWidget(
      wrap(const OpeningStockWizardPage(), [
        productsProvider.overrideWith(
          (ref, query) =>
              Stream.value([ProductWithStock(product: product, stock: 3)]),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('No products need opening stock'), findsOneWidget);
  });

  testWidgets(
    'stock sheet button prints the current balances via the service',
    (tester) async {
      useDesktopViewport(tester);
      final product = sampleProduct();
      final service = _FakeStockSheetService();
      await tester.pumpWidget(
        wrap(const InventoryPage(), [
          productsProvider.overrideWith(
            (ref, query) =>
                Stream.value([ProductWithStock(product: product, stock: 10)]),
          ),
          movementsProvider.overrideWith(
            (ref, filter) => Stream.value(const <MovementWithProduct>[]),
          ),
          stockSheetServiceProvider.overrideWithValue(service),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stock sheet'), findsOneWidget);
      await tester.tap(find.text('Stock sheet'));
      await tester.pumpAndSettle();

      // Both destinations are offered from the sheet.
      expect(find.text('Print stock sheet'), findsOneWidget);
      expect(find.text('Save as PDF'), findsOneWidget);

      await tester.tap(find.text('Print stock sheet'));
      await tester.pumpAndSettle();

      expect(service.printed, isTrue);
      expect(service.printedBytes, isNotNull);
      expect(service.printedBytes!.length, greaterThan(1000));
      expect(find.text('Stock sheet sent to the printer.'), findsOneWidget);
    },
  );

  testWidgets('stock sheet button is disabled when the catalog is empty', (
    tester,
  ) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(
      wrap(const InventoryPage(), [
        productsProvider.overrideWith(
          (ref, query) => Stream.value(const <ProductWithStock>[]),
        ),
        movementsProvider.overrideWith(
          (ref, filter) => Stream.value(const <MovementWithProduct>[]),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Stock sheet'),
    );
    expect(button.onPressed, isNull);
  });
}

class _FakeStockSheetService implements StockSheetService {
  bool printed = false;
  Uint8List? printedBytes;
  bool saved = false;

  @override
  Future<bool> printPdf(Uint8List bytes, {required String name}) async {
    printed = true;
    printedBytes = bytes;
    return true;
  }

  @override
  Future<bool> savePdf(Uint8List bytes, {required String suggestedName}) async {
    saved = true;
    return true;
  }
}
