import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';

/// One line of an original sale being returned.
class ReturnLineRequest {
  const ReturnLineRequest({
    required this.saleItemId,
    required this.productId,
    required this.quantity,
  });

  final String saleItemId;
  final String productId;
  final double quantity;
}

/// A refund of goods from an original sale (§14). The original sale is never
/// modified; stock returns via REFUND movements.
class RefundRequest {
  const RefundRequest({
    required this.originalSaleId,
    required this.lines,
    this.method = PaymentMethod.cash,
    this.reason,
    this.cashierId,
  });

  final String originalSaleId;
  final List<ReturnLineRequest> lines;
  final PaymentMethod method;
  final String? reason;
  final String? cashierId;
}

class CompletedRefund {
  const CompletedRefund({
    required this.refundId,
    required this.refundNumber,
    required this.amount,
    required this.itemCount,
  });

  final String refundId;
  final String refundNumber;
  final double amount;
  final int itemCount;
}

/// An exchange: return goods from an original sale and sell a replacement
/// (§15). The difference is settled through the replacement sale.
class ExchangeRequest {
  const ExchangeRequest({
    required this.originalSaleId,
    required this.returnedLines,
    required this.replacements,
    required this.balancePayments,
    this.cashierId,
  });

  final String originalSaleId;
  final List<ReturnLineRequest> returnedLines;

  /// Replacement product lines chosen by the customer.
  final List<({String productId, double quantity})> replacements;

  /// Real-money payments for the portion the returned goods don't cover.
  final List<PaymentDraft> balancePayments;
  final String? cashierId;
}

class CompletedExchange {
  const CompletedExchange({
    required this.exchangeId,
    required this.exchangeNumber,
    required this.replacementReceiptNumber,
    required this.returnCredit,
    required this.replacementTotal,
    required this.cashBack,
  });

  final String exchangeId;
  final String exchangeNumber;
  final String replacementReceiptNumber;
  final double returnCredit;
  final double replacementTotal;

  /// Cash returned to the customer when the replacement was cheaper.
  final double cashBack;
}

class RefundException implements Exception {
  RefundException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Splits an exchange into its money parts.
class ExchangeBreakdown {
  const ExchangeBreakdown({
    required this.returnCredit,
    required this.replacementTotal,
    required this.balanceDue,
    required this.cashBack,
    required this.exchangeCredit,
  });

  final double returnCredit;
  final double replacementTotal;

  /// Money the customer still owes after their returned goods' value.
  final double balanceDue;

  /// Money the shop owes the customer when the replacement is cheaper.
  final double cashBack;

  /// Share of the replacement covered by the returned goods' value.
  final double exchangeCredit;
}

ExchangeBreakdown computeExchangeBreakdown({
  required double returnCredit,
  required double replacementTotal,
}) {
  final credit = returnCredit < 0 ? 0.0 : returnCredit;
  final due = replacementTotal < 0 ? 0.0 : replacementTotal;
  return ExchangeBreakdown(
    returnCredit: credit,
    replacementTotal: due,
    balanceDue: due > credit ? due - credit : 0,
    cashBack: credit > due ? credit - due : 0,
    exchangeCredit: credit < due ? credit : due,
  );
}
