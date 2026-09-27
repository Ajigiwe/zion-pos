import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/features/dashboard/data/dashboard_repository.dart';
import 'package:instrument_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:instrument_pos/features/dashboard/presentation/dashboard_providers.dart';

DashboardSnapshot snapshot({List<LowStockProduct> lowStock = const []}) {
  return DashboardSnapshot(
    cashTotal: 130,
    mobileMoneyTotal: 45,
    cashPayments: 2,
    mobileMoneyPayments: 1,
    cashRefunds: 10,
    mobileMoneyRefunds: 5,
    cashRefundCount: 1,
    mobileMoneyRefundCount: 1,
    saleCount: 2,
    lowStock: lowStock,
  );
}

Widget harness(DashboardSnapshot value, {VoidCallback? onOpenInventory}) {
  return ProviderScope(
    overrides: [dashboardProvider.overrideWith((ref) async => value)],
    child: MaterialApp(
      home: Scaffold(
        body: DashboardPage(onOpenInventory: onOpenInventory ?? () {}),
      ),
    ),
  );
}

void main() {
  testWidgets('shows takings, method split and sale count', (tester) async {
    await tester.pumpWidget(harness(snapshot()));
    await tester.pumpAndSettle();

    expect(find.text("Today's takings"), findsOneWidget);
    expect(find.text('GHS 175.00'), findsOneWidget);
    expect(find.text('GHS 130.00'), findsOneWidget);
    expect(find.text('GHS 45.00'), findsOneWidget);
    expect(find.text('Cash'), findsNWidgets(2));
    expect(find.text('Mobile Money'), findsNWidgets(2));
    expect(find.text('2 payment(s) today'), findsOneWidget);
    expect(find.text('Sales today'), findsOneWidget);
    expect(find.text('2 completed'), findsOneWidget);
  });

  testWidgets('tracks refunds by method alongside sales', (tester) async {
    await tester.pumpWidget(harness(snapshot()));
    await tester.pumpAndSettle();

    expect(find.text('Refunds today'), findsOneWidget);
    expect(find.text('2 refund(s) total'), findsOneWidget);
    expect(find.text('GHS 10.00'), findsOneWidget);
    expect(find.text('GHS 5.00'), findsOneWidget);
    expect(find.text('1 refund(s) today'), findsNWidgets(2));
  });

  testWidgets('lists low stock and jumps to inventory', (tester) async {
    var jumped = false;
    await tester.pumpWidget(
      harness(
        snapshot(
          lowStock: const [
            LowStockProduct(
              productId: 'p-batt',
              name: 'Battery',
              stock: 0,
              reorderLevel: 0,
            ),
            LowStockProduct(
              productId: 'p-drum',
              name: 'Drum Head',
              stock: 4,
              reorderLevel: 5,
            ),
          ],
        ),
        onOpenInventory: () => jumped = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Low stock alerts'), findsOneWidget);
    expect(find.text('Battery'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.text('Drum Head'), findsOneWidget);
    expect(find.text('Reorder at 5'), findsOneWidget);
    expect(find.text('0 left'), findsOneWidget);
    expect(find.text('4 left'), findsOneWidget);
    expect(find.text('All stock levels are healthy.'), findsNothing);

    final openInventory = find.text('Open Inventory');
    await tester.scrollUntilVisible(openInventory, 200);
    await tester.ensureVisible(openInventory);
    await tester.pumpAndSettle();
    await tester.tap(openInventory);
    expect(jumped, isTrue);
  });

  testWidgets('shows the healthy state when nothing is low', (tester) async {
    await tester.pumpWidget(harness(snapshot(lowStock: const [])));
    await tester.pumpAndSettle();

    expect(find.text('Low stock alerts'), findsOneWidget);
    expect(find.text('All stock levels are healthy.'), findsOneWidget);
    expect(find.text('Open Inventory'), findsNothing);
  });
}
