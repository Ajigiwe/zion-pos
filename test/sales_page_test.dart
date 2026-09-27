import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';
import 'package:instrument_pos/features/sales/data/sales_repository.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';
import 'package:instrument_pos/features/sales/presentation/sales_page.dart';
import 'package:instrument_pos/features/sales/presentation/sales_providers.dart';

import 'test_users.dart';

Product sampleProduct({double price = 5800, double stock = 5}) => Product(
  id: 'p1',
  sku: 'YAM-PSR-E473',
  barcode: null,
  name: 'Yamaha PSR-E473',
  categoryId: null,
  brandId: null,
  description: null,
  costPrice: 4500,
  sellingPrice: price,
  taxRate: 0,
  reorderLevel: 0,
  trackingType: ProductTrackingType.quantity,
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

class FakeSaleRepository implements SaleRepository {
  FakeSaleRepository({this.completed});

  CompletedSale? completed;

  @override
  Future<CompletedSale> completeSale(SaleRequest request) async {
    if (completed == null) {
      throw PaymentException('Not configured');
    }
    return completed!;
  }

  @override
  Stream<List<Sale>> watchRecentSales() => const Stream.empty();

  @override
  Future<SaleDetail> loadSaleDetail(String saleId) {
    throw UnimplementedError();
  }
}

void useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('register starts with an empty cart and disabled checkout', (
    tester,
  ) async {
    useDesktopViewport(tester);
    final product = sampleProduct();
    final fake = FakeSaleRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(testUser()),
          productsProvider.overrideWith(
            (ref, query) =>
                Stream.value([ProductWithStock(product: product, stock: 5)]),
          ),
          salesRepositoryProvider.overrideWithValue(fake),
        ],
        child: const MaterialApp(home: Scaffold(body: SalesPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Cart is empty.\nTap products to add them.'),
      findsOneWidget,
    );
    expect(find.text('Yamaha PSR-E473'), findsOneWidget);
  });

  testWidgets('cashier adds a product and completes a cash sale with change', (
    tester,
  ) async {
    useDesktopViewport(tester);
    final product = sampleProduct();
    final fake = FakeSaleRepository(
      completed: const CompletedSale(
        receiptNumber: 'SA-00001',
        total: 5800,
        change: 200,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(testUser()),
          productsProvider.overrideWith(
            (ref, query) =>
                Stream.value([ProductWithStock(product: product, stock: 5)]),
          ),
          salesRepositoryProvider.overrideWithValue(fake),
        ],
        child: const MaterialApp(home: Scaffold(body: SalesPage())),
      ),
    );
    await tester.pumpAndSettle();

    // Add the product to the cart.
    await tester.tap(find.widgetWithText(ListTile, 'Yamaha PSR-E473'));
    await tester.pumpAndSettle();
    expect(find.text('GHS 5800.00'), findsWidgets);

    // Complete sale is disabled until payment covers the total.
    final completeButton = find.widgetWithText(FilledButton, 'Complete sale');
    expect(tester.widget<FilledButton>(completeButton).onPressed, isNull);

    // Tender cash GHS 6000.
    await tester.enterText(
      find.widgetWithText(TextField, 'Amount received'),
      '6000',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Cash GHS 6000.00'), findsOneWidget);
    expect(find.text('GHS 200.00'), findsWidgets); // change due

    // Complete the sale. The button shows a spinner while saving, so pump
    // with explicit durations instead of pumpAndSettle.
    await tester.tap(find.text('Complete sale'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('Sale SA-00001 complete (GHS 5800.00) · Change due: GHS 200.00'),
      findsOneWidget,
    );
    expect(
      find.text('Cart is empty.\nTap products to add them.'),
      findsOneWidget,
    );
  });

  testWidgets('stock limit blocks adding more than available', (tester) async {
    useDesktopViewport(tester);
    final product = sampleProduct();
    final fake = FakeSaleRepository(
      completed: const CompletedSale(
        receiptNumber: 'SA-00001',
        total: 5800,
        change: 0,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(testUser()),
          productsProvider.overrideWith(
            (ref, query) =>
                Stream.value([ProductWithStock(product: product, stock: 1)]),
          ),
          salesRepositoryProvider.overrideWithValue(fake),
        ],
        child: const MaterialApp(home: Scaffold(body: SalesPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Yamaha PSR-E473'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Yamaha PSR-E473'));
    await tester.pumpAndSettle();

    expect(find.text('Only 1 in stock for Yamaha PSR-E473.'), findsOneWidget);
  });

  testWidgets('history view shows completed sales and sale detail', (
    tester,
  ) async {
    useDesktopViewport(tester);
    final product = sampleProduct();
    final sale = Sale(
      id: 's1',
      receiptNumber: 'SA-00001',
      customerId: null,
      cashierId: null,
      subtotal: 5800,
      discount: 0,
      tax: 0,
      total: 5800,
      paymentStatus: 'PAID',
      saleStatus: 'COMPLETED',
      isSynced: true,
      createdAt: DateTime(2026, 1, 1, 14, 5),
      updatedAt: DateTime(2026, 1, 1, 14, 5),
    );
    final item = SaleItem(
      id: 'i1',
      saleId: sale.id,
      productId: product.id,
      quantity: 1,
      unitPrice: 5800,
      discount: 0,
      tax: 0,
      subtotal: 5800,
      serialNumberId: null,
    );
    final detail = SaleDetail(
      sale: sale,
      items: [(item: item, productName: product.name)],
      payments: [
        Payment(
          id: 'pay1',
          saleId: sale.id,
          paymentMethod: PaymentMethod.cash,
          amount: 5800,
          reference: null,
          createdAt: DateTime(2026, 1, 1, 14, 5),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(testUser()),
          productsProvider.overrideWith(
            (ref, query) =>
                Stream.value([ProductWithStock(product: product, stock: 5)]),
          ),
          recentSalesProvider.overrideWith((ref) => Stream.value([sale])),
          saleDetailProvider.overrideWith((ref, id) async => detail),
        ],
        child: const MaterialApp(home: Scaffold(body: SalesPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.textContaining('SA-00001'), findsWidgets);

    await tester.tap(find.textContaining('SA-00001').first);
    await tester.pumpAndSettle();
    expect(find.text('Sale SA-00001'), findsOneWidget);
    expect(find.text('Yamaha PSR-E473 × 1'), findsOneWidget);
  });
}
