import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/dashboard/data/dashboard_repository.dart';
import 'package:instrument_pos/features/dashboard/presentation/dashboard_providers.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';
import 'package:instrument_pos/features/sales/presentation/sales_providers.dart';
import 'package:instrument_pos/home_shell.dart';

Widget harness(Stream<int> count) {
  const emptyDashboard = DashboardSnapshot(
    cashTotal: 0,
    mobileMoneyTotal: 0,
    cashPayments: 0,
    mobileMoneyPayments: 0,
    cashRefunds: 0,
    mobileMoneyRefunds: 0,
    cashRefundCount: 0,
    mobileMoneyRefundCount: 0,
    saleCount: 0,
    lowStock: [],
  );
  return ProviderScope(
    overrides: [
      productsProvider.overrideWith(
        (ref, query) => Stream.value(const <ProductWithStock>[]),
      ),
      recentSalesProvider.overrideWith((ref) => Stream.value(const <Sale>[])),
      lowStockCountProvider.overrideWith((ref) => count),
      dashboardProvider.overrideWith((ref) async => emptyDashboard),
    ],
    child: const MaterialApp(home: HomeShell()),
  );
}

void main() {
  testWidgets('shows the low-stock count on the Dashboard entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(Stream.value(3)));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // Tapping Dashboard opens the page and the badge stays visible.
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    expect(find.text("Today's takings"), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('no badge when nothing is low', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(Stream.value(0)));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });
}
