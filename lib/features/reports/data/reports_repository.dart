import 'package:drift/drift.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/reports/domain/report_models.dart';

/// Aggregations for the Reports page (design doc §34): financial
/// reconciliation, sales/refunds by cashier, sales by product and refund
/// reasons over a date range. Pure reads — nothing here ever writes.
class ReportsRepository {
  ReportsRepository(this._db);

  final AppDatabase _db;

  Future<ReportData> load(ReportRange range) async {
    final financial = await _financialSummary(range);
    final byCashier = await _salesByCashier(range);
    final byProduct = await _salesByProduct(range);
    final refundsByCashier = await _refundsByCashier(range);
    final refundsByProduct = await _refundsByProduct(range);
    final refundReasons = await _refundReasons(range);

    return ReportData(
      range: range,
      financial: financial,
      byCashier: byCashier,
      byProduct: byProduct,
      refundsByCashier: refundsByCashier,
      refundsByProduct: refundsByProduct,
      refundReasons: refundReasons,
    );
  }

  Expression<bool> _inRange(Expression<DateTime> column, ReportRange range) =>
      column.isBiggerOrEqualValue(range.start) &
      column.isSmallerThanValue(range.end);

  /// textEnum columns store the enum name; tolerate unknown values by mapping
  /// them to cash (they still count towards reconciliation rather than being
  /// silently dropped).
  PaymentMethod _methodOf(String? raw) {
    for (final method in PaymentMethod.values) {
      if (method.name == raw) return method;
    }
    return PaymentMethod.cash;
  }

  Future<FinancialSummary> _financialSummary(ReportRange range) async {
    final salesRow =
        await (_db.selectOnly(_db.sales)
              ..addColumns([
                _db.sales.total.sum(),
                _db.sales.discount.sum(),
                _db.sales.id.count(),
              ])
              ..where(_inRange(_db.sales.createdAt, range)))
            .getSingle();

    final paymentRows =
        await (_db.selectOnly(_db.payments)
              ..addColumns([
                _db.payments.paymentMethod,
                _db.payments.amount.sum(),
                _db.payments.id.count(),
              ])
              ..where(_inRange(_db.payments.createdAt, range))
              ..groupBy([_db.payments.paymentMethod]))
            .get();

    final refundRows =
        await (_db.selectOnly(_db.refunds)
              ..addColumns([
                _db.refunds.refundMethod,
                _db.refunds.amount.sum(),
                _db.refunds.id.count(),
              ])
              ..where(_inRange(_db.refunds.createdAt, range))
              ..groupBy([_db.refunds.refundMethod]))
            .get();

    return FinancialSummary(
      grossSales: salesRow.read(_db.sales.total.sum()) ?? 0,
      discounts: salesRow.read(_db.sales.discount.sum()) ?? 0,
      saleCount: salesRow.read(_db.sales.id.count()) ?? 0,
      paymentsByMethod: {
        for (final row in paymentRows)
          _methodOf(row.read(_db.payments.paymentMethod)):
              row.read(_db.payments.amount.sum()) ?? 0,
      },
      paymentCountsByMethod: {
        for (final row in paymentRows)
          _methodOf(row.read(_db.payments.paymentMethod)):
              row.read(_db.payments.id.count()) ?? 0,
      },
      refundsTotal: refundRows.fold(
        0.0,
        (sum, row) => sum + (row.read(_db.refunds.amount.sum()) ?? 0),
      ),
      refundCount: refundRows.fold(
        0,
        (sum, row) => sum + (row.read(_db.refunds.id.count()) ?? 0),
      ),
      refundsByMethod: {
        for (final row in refundRows)
          _methodOf(row.read(_db.refunds.refundMethod)):
              row.read(_db.refunds.amount.sum()) ?? 0,
      },
      refundCountsByMethod: {
        for (final row in refundRows)
          _methodOf(row.read(_db.refunds.refundMethod)):
              row.read(_db.refunds.id.count()) ?? 0,
      },
    );
  }

  Future<List<CashierSalesReport>> _salesByCashier(ReportRange range) async {
    final cashier = _db.alias(_db.users, 'report_cashiers');
    final rows =
        await (_db.selectOnly(_db.sales)
              ..join([
                leftOuterJoin(
                  cashier,
                  cashier.id.equalsExp(_db.sales.cashierId),
                ),
              ])
              ..addColumns([
                _db.sales.cashierId,
                cashier.displayName,
                _db.sales.id.count(),
                _db.sales.total.sum(),
              ])
              ..where(_inRange(_db.sales.createdAt, range))
              ..groupBy([_db.sales.cashierId]))
            .get();
    return [
      for (final row in rows)
        CashierSalesReport(
          cashierName:
              row.read(cashier.displayName) ??
              row.read(_db.sales.cashierId) ??
              'Unknown',
          saleCount: row.read(_db.sales.id.count()) ?? 0,
          total: row.read(_db.sales.total.sum()) ?? 0,
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));
  }

  Future<List<ProductSalesReport>> _salesByProduct(ReportRange range) async {
    final rows =
        await (_db.selectOnly(_db.saleItems)
              ..join([
                innerJoin(
                  _db.products,
                  _db.products.id.equalsExp(_db.saleItems.productId),
                ),
                innerJoin(
                  _db.sales,
                  _db.sales.id.equalsExp(_db.saleItems.saleId),
                ),
              ])
              ..addColumns([
                _db.saleItems.productId,
                _db.products.name,
                _db.products.sku,
                _db.saleItems.quantity.sum(),
                _db.saleItems.subtotal.sum(),
              ])
              ..where(_inRange(_db.sales.createdAt, range))
              ..groupBy([_db.saleItems.productId]))
            .get();
    return [
      for (final row in rows)
        ProductSalesReport(
          productId: row.read(_db.saleItems.productId)!,
          name: row.read(_db.products.name)!,
          sku: row.read(_db.products.sku)!,
          quantity: row.read(_db.saleItems.quantity.sum()) ?? 0,
          revenue: row.read(_db.saleItems.subtotal.sum()) ?? 0,
        ),
    ]..sort((a, b) => b.revenue.compareTo(a.revenue));
  }

  Future<List<CashierSalesReport>> _refundsByCashier(ReportRange range) async {
    final cashier = _db.alias(_db.users, 'report_refund_cashiers');
    final rows =
        await (_db.selectOnly(_db.refunds)
              ..join([
                leftOuterJoin(
                  cashier,
                  cashier.id.equalsExp(_db.refunds.cashierId),
                ),
              ])
              ..addColumns([
                _db.refunds.cashierId,
                cashier.displayName,
                _db.refunds.id.count(),
                _db.refunds.amount.sum(),
              ])
              ..where(_inRange(_db.refunds.createdAt, range))
              ..groupBy([_db.refunds.cashierId]))
            .get();
    return [
      for (final row in rows)
        CashierSalesReport(
          cashierName:
              row.read(cashier.displayName) ??
              row.read(_db.refunds.cashierId) ??
              'Unknown',
          saleCount: row.read(_db.refunds.id.count()) ?? 0,
          total: row.read(_db.refunds.amount.sum()) ?? 0,
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));
  }

  Future<List<RefundProductReport>> _refundsByProduct(ReportRange range) async {
    final rows =
        await (_db.selectOnly(_db.refundItems)
              ..join([
                innerJoin(
                  _db.products,
                  _db.products.id.equalsExp(_db.refundItems.productId),
                ),
                innerJoin(
                  _db.refunds,
                  _db.refunds.id.equalsExp(_db.refundItems.refundId),
                ),
              ])
              ..addColumns([
                _db.refundItems.productId,
                _db.products.name,
                _db.refundItems.quantity.sum(),
                _db.refundItems.subtotal.sum(),
              ])
              ..where(_inRange(_db.refunds.createdAt, range))
              ..groupBy([_db.refundItems.productId]))
            .get();
    return [
      for (final row in rows)
        RefundProductReport(
          productId: row.read(_db.refundItems.productId)!,
          name: row.read(_db.products.name)!,
          quantity: row.read(_db.refundItems.quantity.sum()) ?? 0,
          amount: row.read(_db.refundItems.subtotal.sum()) ?? 0,
        ),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
  }

  Future<List<RefundReasonReport>> _refundReasons(ReportRange range) async {
    final rows =
        await (_db.selectOnly(_db.refunds)
              ..addColumns([
                _db.refunds.reason,
                _db.refunds.id.count(),
                _db.refunds.amount.sum(),
              ])
              ..where(_inRange(_db.refunds.createdAt, range))
              ..groupBy([_db.refunds.reason]))
            .get();
    return [
      for (final row in rows)
        RefundReasonReport(
          reason: row.read(_db.refunds.reason)?.trim().isNotEmpty == true
              ? row.read(_db.refunds.reason)!.trim()
              : 'Not specified',
          count: row.read(_db.refunds.id.count()) ?? 0,
          amount: row.read(_db.refunds.amount.sum()) ?? 0,
        ),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
  }
}
