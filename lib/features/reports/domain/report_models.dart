import 'package:instrument_pos/core/database/tables.dart';

/// Preset date ranges selectable on the Reports page. Enum identity makes it
/// a safe Riverpod family key.
enum TimelineRange {
  today,
  last7Days,
  last30Days;

  /// Resolves to [start, end) — end is exclusive midnight of the next day.
  ReportRange resolve(DateTime now) => switch (this) {
    TimelineRange.today => ReportRange(
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day + 1),
    ),
    TimelineRange.last7Days => ReportRange(
      start: DateTime(now.year, now.month, now.day - 6),
      end: DateTime(now.year, now.month, now.day + 1),
    ),
    TimelineRange.last30Days => ReportRange(
      start: DateTime(now.year, now.month, now.day - 29),
      end: DateTime(now.year, now.month, now.day + 1),
    ),
  };

  String get label => switch (this) {
    TimelineRange.today => 'Today',
    TimelineRange.last7Days => 'Last 7 days',
    TimelineRange.last30Days => 'Last 30 days',
  };
}

/// A half-open date window: [start, end).
class ReportRange {
  const ReportRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  /// Human label, e.g. `2026-09-05` or `2026-08-07 to 2026-09-05`.
  String get label {
    final lastDay = end.subtract(const Duration(days: 1));
    final startLabel = _isoDate(start);
    if (_isoDate(lastDay) == startLabel) return startLabel;
    return '$startLabel to ${_isoDate(lastDay)}';
  }

  static String _isoDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

/// Financial reconciliation per design doc §34: total sales, money received
/// per payment method, refunds, and the net figure.
class FinancialSummary {
  const FinancialSummary({
    required this.grossSales,
    required this.discounts,
    required this.saleCount,
    required this.paymentsByMethod,
    required this.paymentCountsByMethod,
    required this.refundsTotal,
    required this.refundCount,
    required this.refundsByMethod,
    required this.refundCountsByMethod,
  });

  /// Sum of sale totals in the range (value of goods sold).
  final double grossSales;

  /// Sum of sale-level discounts given.
  final double discounts;
  final int saleCount;

  /// Money received per payment method. [PaymentMethod.exchangeCredit] is the
  /// value of returned goods used to pay for replacements — not cash received.
  final Map<PaymentMethod, double> paymentsByMethod;
  final Map<PaymentMethod, int> paymentCountsByMethod;

  final double refundsTotal;
  final int refundCount;
  final Map<PaymentMethod, double> refundsByMethod;
  final Map<PaymentMethod, int> refundCountsByMethod;

  double moneyByMethod(PaymentMethod method) => paymentsByMethod[method] ?? 0;

  int paymentsByMethodCount(PaymentMethod method) =>
      paymentCountsByMethod[method] ?? 0;

  double refundsByMethodTotal(PaymentMethod method) =>
      refundsByMethod[method] ?? 0;

  int refundsByMethodCount(PaymentMethod method) =>
      refundCountsByMethod[method] ?? 0;

  /// Total sales minus refunds — the "Net Sales" line of design doc §34.
  double get netSales => grossSales - refundsTotal;
}

/// Sales attributed to the cashier who rang them up.
class CashierSalesReport {
  const CashierSalesReport({
    required this.cashierName,
    required this.saleCount,
    required this.total,
  });

  /// Display name; `Unknown` when the sale has no cashier recorded.
  final String cashierName;
  final int saleCount;
  final double total;
}

/// Quantity and revenue per product sold in the range.
class ProductSalesReport {
  const ProductSalesReport({
    required this.productId,
    required this.name,
    required this.sku,
    required this.quantity,
    required this.revenue,
  });

  final String productId;
  final String name;
  final String sku;
  final double quantity;
  final double revenue;
}

/// Quantity and money returned per product in the range.
class RefundProductReport {
  const RefundProductReport({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.amount,
  });

  final String productId;
  final String name;
  final double quantity;
  final double amount;
}

/// Refund counts/amounts grouped by the recorded reason.
class RefundReasonReport {
  const RefundReasonReport({
    required this.reason,
    required this.count,
    required this.amount,
  });

  final String reason;
  final int count;
  final double amount;
}

/// Everything the Reports page renders for one range.
class ReportData {
  const ReportData({
    required this.range,
    required this.financial,
    required this.byCashier,
    required this.byProduct,
    required this.refundsByCashier,
    required this.refundsByProduct,
    required this.refundReasons,
  });

  final ReportRange range;
  final FinancialSummary financial;
  final List<CashierSalesReport> byCashier;
  final List<ProductSalesReport> byProduct;
  final List<CashierSalesReport> refundsByCashier;
  final List<RefundProductReport> refundsByProduct;
  final List<RefundReasonReport> refundReasons;

  bool get isEmpty =>
      financial.saleCount == 0 &&
      financial.refundCount == 0 &&
      financial.paymentsByMethod.isEmpty;
}
