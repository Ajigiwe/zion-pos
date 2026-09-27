import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';

/// One product line the cashier put in the cart.
class CartLine {
  CartLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.taxRate,
  });

  final String productId;
  final String name;
  double quantity;
  final double unitPrice;
  final double taxRate;
}

/// A payment record the cashier captured for the current sale (§12).
class PaymentDraft {
  const PaymentDraft({
    required this.method,
    required this.amount,
    this.reference,
  });

  final PaymentMethod method;
  final double amount;
  final String? reference;
}

extension PaymentMethodLabel on PaymentMethod {
  String get label => switch (this) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.mobileMoney => 'Mobile Money',
    PaymentMethod.card => 'Card',
    PaymentMethod.bankTransfer => 'Bank Transfer',
    PaymentMethod.exchangeCredit => 'Exchange credit',
  };
}

/// Payment methods the store actually accepts — currently cash and mobile
/// money only. Screens must offer exactly these; the enum keeps Card, Bank
/// Transfer and Exchange credit for historical records and for the internal
/// accounting of exchanges.
const List<PaymentMethod> kAcceptedPaymentMethods = [
  PaymentMethod.cash,
  PaymentMethod.mobileMoney,
];

/// Totals for a sale. Prices are treated as tax-inclusive: [taxIncluded] is
/// the VAT portion inside [grossSubtotal], informational for reporting, and
/// total = grossSubtotal − discount.
class SaleTotals {
  const SaleTotals({
    required this.grossSubtotal,
    required this.discount,
    required this.taxIncluded,
    required this.total,
  });

  final double grossSubtotal;
  final double discount;
  final double taxIncluded;
  final double total;
}

/// Computes sale totals from line gross amounts and tax rates (percent).
SaleTotals computeSaleTotals({
  required List<({double gross, double taxRate})> lines,
  required double discount,
}) {
  var gross = 0.0;
  var taxGross = 0.0;
  for (final line in lines) {
    gross += line.gross;
    if (line.taxRate > 0) {
      final factor = line.taxRate / (100 + line.taxRate);
      taxGross += line.gross * factor;
    }
  }
  final safeDiscount = discount.clamp(0.0, gross);
  // A discount proportionally removes both the net and included-tax parts.
  final tax = gross > 0 ? taxGross * ((gross - safeDiscount) / gross) : 0.0;
  return SaleTotals(
    grossSubtotal: gross,
    discount: safeDiscount,
    taxIncluded: tax,
    total: gross - safeDiscount,
  );
}

/// Result returned after the sale transaction committed.
class CompletedSale {
  const CompletedSale({
    required this.receiptNumber,
    required this.total,
    required this.change,
  });

  final String receiptNumber;
  final double total;
  final double change;
}

/// Sale + items + payments loaded for history/receipts.
class SaleDetail {
  const SaleDetail({
    required this.sale,
    required this.items,
    required this.payments,
  });

  final Sale sale;

  /// Line with the product name resolved for display.
  final List<({SaleItem item, String productName})> items;
  final List<Payment> payments;
}

/// Raised when the ledger cannot cover a sale line.
class StockShortageException implements Exception {
  StockShortageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Raised when payments don't cover the sale total.
class PaymentException implements Exception {
  PaymentException(this.message);

  final String message;

  @override
  String toString() => message;
}
