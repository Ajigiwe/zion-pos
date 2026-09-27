import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/presentation/product_edit_page.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';
import 'package:instrument_pos/features/sales/presentation/barcode_scan_dialog.dart';
import 'package:instrument_pos/features/sales/presentation/barcode_scanner_listener.dart';

class _FakeProductsRepository implements ProductsRepository {
  final List<ProductWithStock> products = [
    ProductWithStock(
      product: Product(
        id: 'prod-1',
        name: 'Fender Stratocaster Electric Guitar',
        sku: 'FEN-STRAT-01',
        barcode: '885978123456',
        categoryId: null,
        brandId: null,
        description: null,
        costPrice: 500.0,
        sellingPrice: 799.99,
        taxRate: 0.1,
        reorderLevel: 2,
        trackingType: ProductTrackingType.quantity,
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      stock: 5.0,
    ),
  ];

  @override
  Future<List<ProductWithStock>> findByExact(
    String query, {
    bool includeInactive = false,
  }) async {
    final lower = query.trim().toLowerCase();
    return products.where((p) {
      final barcode = p.product.barcode?.toLowerCase();
      final sku = p.product.sku.toLowerCase();
      final name = p.product.name.toLowerCase();
      return barcode == lower || sku == lower || name == lower;
    }).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BarcodeScannerListener Tests', () {
    testWidgets('buffers fast keystrokes and triggers onBarcodeScanned on Enter',
        (tester) async {
      String? scannedCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BarcodeScannerListener(
              onBarcodeScanned: (code) {
                scannedCode = code;
              },
              child: const Text('Register Body'),
            ),
          ),
        ),
      );

      // Simulate rapid keystrokes from a hardware barcode scanner: '8', '8', '5', '9', 'Enter'
      await tester.sendKeyEvent(LogicalKeyboardKey.digit8, character: '8');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit8, character: '8');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5, character: '5');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9, character: '9');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(scannedCode, '8859');
    });

    testWidgets('ignores single character followed by enter', (tester) async {
      String? scannedCode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BarcodeScannerListener(
              onBarcodeScanned: (code) {
                scannedCode = code;
              },
              child: const Text('Register Body'),
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(scannedCode, isNull);
    });
  });

  group('BarcodeScanDialog Tests', () {
    testWidgets('searches for product by barcode and triggers selection callback',
        (tester) async {
      ProductWithStock? selectedProduct;
      final fakeRepo = _FakeProductsRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productsRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    BarcodeScanDialog.showForSales(
                      context,
                      onProductSelected: (p) => selectedProduct = p,
                    );
                  },
                  child: const Text('Open Scanner'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Scanner'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('READY TO SCAN'), findsOneWidget);
      expect(find.text('Scan Barcode / Fast Ring-Up'), findsOneWidget);

      // Enter barcode in dialog
      await tester.enterText(
        find.byType(TextField).last,
        '885978123456',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Matched product card should be visible
      expect(find.text('Fender Stratocaster Electric Guitar'), findsOneWidget);
      expect(find.text('\$799.99'), findsOneWidget);

      // Tap "Add to Cart"
      await tester.tap(find.text('Add to Cart'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(selectedProduct, isNotNull);
      expect(selectedProduct!.product.name, 'Fender Stratocaster Electric Guitar');
    });

    testWidgets('shows not-found message for unknown barcode', (tester) async {
      final fakeRepo = _FakeProductsRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productsRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    BarcodeScanDialog.showForSales(
                      context,
                      onProductSelected: (_) {},
                    );
                  },
                  child: const Text('Open Scanner'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Scanner'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.enterText(
        find.byType(TextField).last,
        'UNKNOWN99999',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text('No product found with barcode "UNKNOWN99999"'),
        findsOneWidget,
      );
    });
  });

  group('ProductEditPage Barcode Helper Tests', () {
    testWidgets('auto-generate barcode populates valid EAN barcode',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ProductEditPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find Auto-generate barcode button
      final autoGenFinder = find.byTooltip('Auto-generate Barcode');
      expect(autoGenFinder, findsOneWidget);

      await tester.tap(autoGenFinder);
      await tester.pumpAndSettle();

      // Verify that barcode field is populated with a 13-digit EAN barcode starting with '20'
      final barcodeField = find.widgetWithText(TextFormField, 'Barcode');
      final formField = tester.widget<TextFormField>(barcodeField);
      expect(formField.controller?.text.startsWith('20'), isTrue);
      expect(formField.controller?.text.length, 13);
    });
  });
}
