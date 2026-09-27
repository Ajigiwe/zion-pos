import 'package:drift/drift.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/core/store_info.dart';

/// A product whose ledger balance needs attention.
class LowStockProduct {
  const LowStockProduct({
    required this.productId,
    required this.name,
    required this.stock,
    required this.reorderLevel,
  });

  final String productId;
  final String name;
  final double stock;
  final double reorderLevel;

  bool get isOutOfStock => stock <= 0.001;
}

/// A point-in-time read of the till: today's money movement (net of refunds),
/// today's completed-sale count, and the low-stock list.
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.cashTotal,
    required this.mobileMoneyTotal,
    required this.cashPayments,
    required this.mobileMoneyPayments,
    required this.cashRefunds,
    required this.mobileMoneyRefunds,
    required this.cashRefundCount,
    required this.mobileMoneyRefundCount,
    required this.saleCount,
    required this.lowStock,
  });

  final double cashTotal;
  final double mobileMoneyTotal;
  final int cashPayments;
  final int mobileMoneyPayments;

  /// Money returned to customers today, by method.
  final double cashRefunds;
  final double mobileMoneyRefunds;
  final int cashRefundCount;
  final int mobileMoneyRefundCount;

  final int saleCount;
  final List<LowStockProduct> lowStock;

  /// Real money that came in today — cash + mobile money, after refunds.
  double get takingsTotal => cashTotal + mobileMoneyTotal;
}

/// Aggregations for the Dashboard. Pure reads over the sales/payments/refunds
/// ledger plus the stock ledger — nothing here ever writes.
class DashboardRepository {
  DashboardRepository(this._db);

  final AppDatabase _db;

  Future<DashboardSnapshot> load() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));

    final cashPayments = await _paymentStats(PaymentMethod.cash, start, end);
    final momoPayments = await _paymentStats(
      PaymentMethod.mobileMoney,
      start,
      end,
    );
    final cashRefundStats = await _refundStats(PaymentMethod.cash, start, end);
    final momoRefundStats = await _refundStats(
      PaymentMethod.mobileMoney,
      start,
      end,
    );
    final saleCount = await _completedSaleCount(start, end);
    final lowStock = await lowStockProducts();

    return DashboardSnapshot(
      cashTotal: cashPayments.$1 - cashRefundStats.$1,
      mobileMoneyTotal: momoPayments.$1 - momoRefundStats.$1,
      cashPayments: cashPayments.$2,
      mobileMoneyPayments: momoPayments.$2,
      cashRefunds: cashRefundStats.$1,
      mobileMoneyRefunds: momoRefundStats.$1,
      cashRefundCount: cashRefundStats.$2,
      mobileMoneyRefundCount: momoRefundStats.$2,
      saleCount: saleCount,
      lowStock: lowStock,
    );
  }

  /// (amount, number of payment records) received today by one method.
  Future<(double, int)> _paymentStats(
    PaymentMethod method,
    DateTime start,
    DateTime end,
  ) async {
    final query = _db.selectOnly(_db.payments)
      ..addColumns([_db.payments.amount.sum(), _db.payments.id.count()])
      ..where(
        _db.payments.paymentMethod.equalsValue(method) &
            _db.payments.createdAt.isBiggerOrEqualValue(start) &
            _db.payments.createdAt.isSmallerThanValue(end),
      );
    final row = await query.getSingle();
    return (
      row.read(_db.payments.amount.sum()) ?? 0,
      row.read(_db.payments.id.count()) ?? 0,
    );
  }

  /// (amount, number of refund records) paid out today by one method.
  Future<(double, int)> _refundStats(
    PaymentMethod method,
    DateTime start,
    DateTime end,
  ) async {
    final query = _db.selectOnly(_db.refunds)
      ..addColumns([_db.refunds.amount.sum(), _db.refunds.id.count()])
      ..where(
        _db.refunds.refundMethod.equalsValue(method) &
            _db.refunds.createdAt.isBiggerOrEqualValue(start) &
            _db.refunds.createdAt.isSmallerThanValue(end),
      );
    final row = await query.getSingle();
    return (
      row.read(_db.refunds.amount.sum()) ?? 0,
      row.read(_db.refunds.id.count()) ?? 0,
    );
  }

  Future<int> _completedSaleCount(DateTime start, DateTime end) async {
    final query = _db.selectOnly(_db.sales)
      ..addColumns([_db.sales.id.count()])
      ..where(
        _db.sales.createdAt.isBiggerOrEqualValue(start) &
            _db.sales.createdAt.isSmallerThanValue(end),
      );
    final row = await query.getSingle();
    return row.read(_db.sales.id.count()) ?? 0;
  }

  /// Active products at or below their alert level — a product's own reorder
  /// level when set, otherwise the global low-stock threshold from Settings —
  /// or simply out of stock. Scarcest first. Used by the Dashboard page and
  /// the sidebar alert badge.
  Future<List<LowStockProduct>> lowStockProducts() async {
    final thresholdRow =
        await (_db.select(_db.settings)
              ..where((s) => s.key.equals(StoreSettingKeys.lowStockThreshold)))
            .getSingleOrNull();
    final globalThreshold =
        double.tryParse(thresholdRow?.value ?? '') ?? kDefaultLowStockThreshold;

    final products = await (_db.select(
      _db.products,
    )..where((p) => p.isActive.equals(true))).get();

    final balances = await _stockBalances();
    final alerts = <LowStockProduct>[
      for (final product in products)
        if ((balances[product.id] ?? 0) <=
            (product.reorderLevel > 0 ? product.reorderLevel : globalThreshold))
          LowStockProduct(
            productId: product.id,
            name: product.name,
            stock: balances[product.id] ?? 0,
            reorderLevel: product.reorderLevel > 0
                ? product.reorderLevel
                : globalThreshold,
          ),
    ]..sort((a, b) => a.stock.compareTo(b.stock));
    return alerts.length <= 50 ? alerts : alerts.sublist(0, 50);
  }

  /// Sum of all ledger movements per product — the authoritative stock value.
  Future<Map<String, double>> _stockBalances() async {
    final query = _db.selectOnly(_db.stockMovements)
      ..addColumns([
        _db.stockMovements.productId,
        _db.stockMovements.quantity.sum(),
      ])
      ..groupBy([_db.stockMovements.productId]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(_db.stockMovements.productId)!:
            row.read(_db.stockMovements.quantity.sum()) ?? 0,
    };
  }
}
