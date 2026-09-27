import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/inventory/data/inventory_repository.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';
import 'package:instrument_pos/features/refunds/data/refunds_repository.dart';
import 'package:instrument_pos/features/refunds/presentation/refund_flow_page.dart';
import 'package:instrument_pos/features/refunds/presentation/refunds_providers.dart';
import 'package:instrument_pos/features/sales/data/sales_repository.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';
import 'package:instrument_pos/features/sales/presentation/sales_providers.dart';

import 'test_users.dart';

void main() {
  late AppDatabase db;
  late InventoryRepository inventory;
  late DriftSaleRepository salesRepo;
  late DriftRefundsRepository refundsRepo;
  late ProductsRepository productsRepo;
  late String saleId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventory = InventoryRepository(db);
    salesRepo = DriftSaleRepository(db);
    refundsRepo = DriftRefundsRepository(db);
    productsRepo = ProductsRepository(db);

    // Seed products
    await db.into(db.products).insert(
          ProductsCompanion(
            id: const Value('p1'),
            sku: const Value('SKU-1'),
            name: const Value('Original Drum'),
            costPrice: const Value(0),
            sellingPrice: const Value(120),
            taxRate: const Value(0),
            trackingType: const Value(ProductTrackingType.quantity),
            isActive: const Value(true),
            createdAt: Value(DateTime(2026, 1, 1)),
            updatedAt: Value(DateTime(2026, 1, 1)),
          ),
        );

    await db.into(db.products).insert(
          ProductsCompanion(
            id: const Value('p2'),
            sku: const Value('SKU-2'),
            name: const Value('Replacement Speaker'),
            costPrice: const Value(0),
            sellingPrice: const Value(150),
            taxRate: const Value(0),
            trackingType: const Value(ProductTrackingType.quantity),
            isActive: const Value(true),
            createdAt: Value(DateTime(2026, 1, 1)),
            updatedAt: Value(DateTime(2026, 1, 1)),
          ),
        );

    await inventory.recordOpeningStock({'p1': 10, 'p2': 10});

    await salesRepo.completeSale(
      const SaleRequest(
        lines: [(productId: 'p1', quantity: 1)],
        payments: [PaymentDraft(method: PaymentMethod.cash, amount: 120)],
      ),
    );
    saleId = (await salesRepo.watchRecentSales().first).first.id;
  });

  tearDown(() => db.close());

  testWidgets(
      'Exchange flow renders cards, allows searching and adding replacements, auto-fills balance due',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          salesRepositoryProvider.overrideWithValue(salesRepo),
          refundsRepositoryProvider.overrideWithValue(refundsRepo),
          productsRepositoryProvider.overrideWithValue(productsRepo),
          currentUserProvider.overrideWithValue(testUser()),
        ],
        child: MaterialApp(
          home: RefundFlowPage(
            saleId: saleId,
            mode: RefundFlowMode.exchange,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Check step cards
    expect(find.text('1. Select items being returned'), findsOneWidget);
    expect(find.text('2. Select replacement product'), findsOneWidget);
    expect(find.text('3. Exchange Settlement'), findsOneWidget);

    // Click Return on Original Drum
    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();

    // Verify Return Credit is GHS 120.00
    expect(find.text('GHS 120.00'), findsWidgets);

    // Catalog should not show inline product list by default
    expect(find.text('Replacement Speaker'), findsNothing);

    // Search for replacement product
    final searchInput = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText?.contains('Type product') == true,
    );
    expect(searchInput, findsOneWidget);

    await tester.enterText(searchInput, 'Replacement');
    await tester.pumpAndSettle();

    // Product search result appears
    expect(find.text('Replacement Speaker'), findsOneWidget);

    // Click Add
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Check balance payment auto-filled to 30.00
    expect(find.text('Customer pays difference:'), findsOneWidget);
    // Scroll down to submit button
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    final submitButtonText = find.text('Complete Exchange (Pay GHS 30.00)');
    expect(submitButtonText, findsOneWidget);

    // Complete Exchange
    await tester.tap(submitButtonText);
    await tester.pumpAndSettle();

    // Exchange completes and screen pops
    expect(find.byType(RefundFlowPage), findsNothing);
  });
}
