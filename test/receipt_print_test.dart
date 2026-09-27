import 'dart:typed_data';

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
import 'package:instrument_pos/features/sales/presentation/receipt_print_service.dart';
import 'package:instrument_pos/features/sales/presentation/sales_page.dart';
import 'package:instrument_pos/features/sales/presentation/sales_providers.dart';

import 'test_users.dart';

class _CapturingPrintService implements ReceiptPrintService {
  String? lastName;
  Uint8List? lastBytes;
  int calls = 0;
  bool result = true;

  @override
  Future<bool> printPdf(Uint8List bytes, {required String name}) async {
    calls++;
    lastName = name;
    lastBytes = bytes;
    return result;
  }
}

class _CapturingSaleRepository implements SaleRepository {
  @override
  Future<CompletedSale> completeSale(SaleRequest request) async {
    return const CompletedSale(
      receiptNumber: 'SA-00001',
      total: 5800,
      change: 0,
    );
  }

  @override
  Stream<List<Sale>> watchRecentSales() => const Stream.empty();

  @override
  Future<SaleDetail> loadSaleDetail(String saleId) {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('completing a sale automatically prints the receipt immediately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final product = Product(
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
    final printer = _CapturingPrintService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(testUser()),
          productsProvider.overrideWith(
            (ref, query) =>
                Stream.value([ProductWithStock(product: product, stock: 5)]),
          ),
          salesRepositoryProvider.overrideWithValue(_CapturingSaleRepository()),
          receiptPrintServiceProvider.overrideWithValue(printer),
        ],
        child: const MaterialApp(home: Scaffold(body: SalesPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Yamaha PSR-E473'));
    await tester.pumpAndSettle();

    // Tender the exact amount so checkout becomes available.
    await tester.enterText(
      find.widgetWithText(TextField, 'Amount received'),
      '5800',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Cash GHS 5800.00'), findsOneWidget);

    // Completing the sale automatically triggers printing and resets cart.
    await tester.tap(find.text('Complete sale'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(printer.calls, 1);
    expect(printer.lastName, 'Receipt SA-00001');
    expect(printer.lastBytes, isNotNull);
    expect(String.fromCharCodes(printer.lastBytes!.take(5)), '%PDF-');
    expect(find.text('Sale SA-00001 complete (GHS 5800.00)'), findsOneWidget);
    expect(
      find.text('Cart is empty.\nTap products to add them.'),
      findsOneWidget,
    );
  });
}
