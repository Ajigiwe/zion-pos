import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/reports/domain/report_models.dart';
import 'package:instrument_pos/features/reports/presentation/report_export_service.dart';
import 'package:instrument_pos/features/reports/presentation/reports_page.dart';
import 'package:instrument_pos/features/reports/presentation/reports_providers.dart';

import 'test_users.dart';

class FakeExportService implements ReportExportService {
  String? lastContents;
  bool shouldSave = true;

  @override
  Future<bool> saveCsv(String contents, {required String suggestedName}) async {
    lastContents = contents;
    return shouldSave;
  }
}

ReportData sampleData() {
  final range = ReportRange(
    start: DateTime(2026, 9, 5),
    end: DateTime(2026, 9, 6),
  );
  return ReportData(
    range: range,
    financial: FinancialSummary(
      grossSales: 320,
      discounts: 20,
      saleCount: 3,
      paymentsByMethod: {
        PaymentMethod.cash: 220,
        PaymentMethod.mobileMoney: 80,
      },
      paymentCountsByMethod: {
        PaymentMethod.cash: 2,
        PaymentMethod.mobileMoney: 1,
      },
      refundsTotal: 50,
      refundCount: 1,
      refundsByMethod: {PaymentMethod.cash: 50},
      refundCountsByMethod: {PaymentMethod.cash: 1},
    ),
    byCashier: const [
      CashierSalesReport(cashierName: 'Kofi', saleCount: 2, total: 220),
    ],
    byProduct: const [
      ProductSalesReport(
        productId: 'p1',
        name: 'Drum',
        sku: 'SKU-1',
        quantity: 4,
        revenue: 320,
      ),
    ],
    refundsByCashier: const [
      CashierSalesReport(cashierName: 'Ama', saleCount: 1, total: 50),
    ],
    refundsByProduct: const [
      RefundProductReport(
        productId: 'p1',
        name: 'Drum',
        quantity: 1,
        amount: 50,
      ),
    ],
    refundReasons: const [
      RefundReasonReport(reason: 'Defective', count: 1, amount: 50),
    ],
  );
}

Widget harness({
  required ReportData? data,
  String role = 'OWNER',
  FakeExportService? export,
}) {
  return ProviderScope(
    overrides: [
      if (data != null) reportDataProvider.overrideWith((ref) async => data),
      if (export != null) reportExportServiceProvider.overrideWithValue(export),
      currentUserProvider.overrideWithValue(testUser(role: role)),
    ],
    child: const MaterialApp(home: Scaffold(body: ReportsPage())),
  );
}

void main() {
  testWidgets('renders summary cards, tables and refund sections', (
    tester,
  ) async {
    await tester.pumpWidget(harness(data: sampleData()));
    await tester.pumpAndSettle();

    // Above the fold: header, summary cards, payments section.
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('GHS 320.00'), findsOneWidget);
    expect(find.text('Net sales'), findsOneWidget);
    expect(find.text('GHS 270.00'), findsOneWidget);
    expect(find.textContaining('Payments received'), findsOneWidget);
    expect(find.text('GHS 50.00'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);

    // Scroll to the breakdown tables (lazy ListView builds them on demand).
    await tester.scrollUntilVisible(find.text('Sales by product'), 200);
    expect(find.text('Sales by product'), findsOneWidget);
    expect(find.text('Drum'), findsOneWidget);
    expect(find.text('Kofi'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Defective'), 200);
    expect(find.text('Refunds by product'), findsOneWidget);
    expect(find.text('Defective'), findsOneWidget);
  });

  testWidgets('hides zero rows in payment sections but keeps tables', (
    tester,
  ) async {
    final data = sampleData();
    await tester.pumpWidget(harness(data: data));
    await tester.pumpAndSettle();

    // card / bankTransfer / exchangeCredit have no money in this period.
    expect(find.text('Card'), findsNothing);
    expect(find.text('Bank transfer'), findsNothing);
  });

  testWidgets('shows the empty period state', (tester) async {
    final data = ReportData(
      range: ReportRange(
        start: DateTime(2026, 9, 5),
        end: DateTime(2026, 9, 6),
      ),
      financial: FinancialSummary(
        grossSales: 0,
        discounts: 0,
        saleCount: 0,
        paymentsByMethod: {},
        paymentCountsByMethod: {},
        refundsTotal: 0,
        refundCount: 0,
        refundsByMethod: {},
        refundCountsByMethod: {},
      ),
      byCashier: const [],
      byProduct: const [],
      refundsByCashier: const [],
      refundsByProduct: const [],
      refundReasons: const [],
    );
    await tester.pumpWidget(harness(data: data));
    await tester.pumpAndSettle();

    expect(find.text('No sales or refunds in this period.'), findsOneWidget);
    expect(find.text('Export CSV'), findsNothing);
  });

  testWidgets('switching the range reloads the report', (tester) async {
    final emptyData = ReportData(
      range: ReportRange(
        start: DateTime(2026, 8, 30),
        end: DateTime(2026, 9, 6),
      ),
      financial: FinancialSummary(
        grossSales: 0,
        discounts: 0,
        saleCount: 0,
        paymentsByMethod: {},
        paymentCountsByMethod: {},
        refundsTotal: 0,
        refundCount: 0,
        refundsByMethod: {},
        refundCountsByMethod: {},
      ),
      byCashier: const [],
      byProduct: const [],
      refundsByCashier: const [],
      refundsByProduct: const [],
      refundReasons: const [],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportDataProvider.overrideWith(
            (ref) async =>
                ref.watch(selectedReportRangeProvider) ==
                    TimelineRange.last7Days
                ? emptyData
                : sampleData(),
          ),
          currentUserProvider.overrideWithValue(testUser()),
        ],
        child: const MaterialApp(home: Scaffold(body: ReportsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GHS 320.00'), findsOneWidget);

    await tester.tap(find.text('Last 7 days'));
    await tester.pumpAndSettle();

    expect(find.text('GHS 320.00'), findsNothing);
    expect(find.text('No sales or refunds in this period.'), findsOneWidget);
  });

  testWidgets('hides the export button on empty data', (tester) async {
    final data = ReportData(
      range: ReportRange(
        start: DateTime(2026, 9, 5),
        end: DateTime(2026, 9, 6),
      ),
      financial: FinancialSummary(
        grossSales: 0,
        discounts: 0,
        saleCount: 0,
        paymentsByMethod: {},
        paymentCountsByMethod: {},
        refundsTotal: 0,
        refundCount: 0,
        refundsByMethod: {},
        refundCountsByMethod: {},
      ),
      byCashier: const [],
      byProduct: const [],
      refundsByCashier: const [],
      refundsByProduct: const [],
      refundReasons: const [],
    );
    await tester.pumpWidget(harness(data: data));
    await tester.pumpAndSettle();

    expect(find.text('Export CSV'), findsNothing);
  });

  testWidgets('cashier role is denied access', (tester) async {
    await tester.pumpWidget(harness(data: sampleData(), role: 'CASHIER'));
    await tester.pumpAndSettle();

    expect(find.text('Reports'), findsOneWidget);
    expect(find.textContaining('permission'), findsOneWidget);
    expect(find.text('Export CSV'), findsNothing);
  });

  testWidgets('export writes the full workbook CSV', (tester) async {
    final export = FakeExportService();
    await tester.pumpWidget(harness(data: sampleData(), export: export));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Export CSV'));
    await tester.pumpAndSettle();

    expect(export.lastContents, isNotNull);
    expect(export.lastContents!, contains('Financial reconciliation'));
    expect(export.lastContents!, contains('Sales by Cashier'));
    expect(export.lastContents!, contains('Refund Reasons'));
  });
}
