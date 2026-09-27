import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/refunds/presentation/refunds_page.dart';
import 'package:instrument_pos/features/sales/presentation/sales_providers.dart';

import 'test_users.dart';

Sale sampleSale() => Sale(
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
  createdAt: DateTime(2026, 1, 1, 10, 0),
  updatedAt: DateTime(2026, 1, 1, 10, 0),
  rev: 1, dirty: false,
);

void main() {
  testWidgets('shows a helpful empty state when there are no sales', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(testUser()),
          recentSalesProvider.overrideWith(
            (ref) => Stream.value(const <Sale>[]),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: RefundsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No sales yet'), findsOneWidget);
  });

  testWidgets('a cashier cannot refund but can exchange', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            testUser(role: 'CASHIER', displayName: 'Cashier One'),
          ),
          recentSalesProvider.overrideWith(
            (ref) => Stream.value([sampleSale()]),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: RefundsPage())),
      ),
    );
    await tester.pumpAndSettle();

    final refundButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Refund'),
    );
    expect(refundButton.onPressed, isNull);

    final exchangeButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Exchange'),
    );
    expect(exchangeButton.onPressed, isNotNull);
  });
}
