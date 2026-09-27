import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/sales/domain/receipt_customization.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';

/// One purchased line shown on a receipt.
typedef ReceiptLine = ({String name, double quantity, double unitPrice});

/// Everything a receipt shows, structured. Single source for the on-screen
/// paper-look view, the printed 80 mm PDF and (legacy) text export, so all
/// three can never disagree on amounts or layout order.
class ReceiptContent {
  const ReceiptContent({
    required this.store,
    required this.receiptNumber,
    required this.createdAt,
    required this.totals,
    required this.lines,
    required this.payments,
    this.title = 'RECEIPT',
    this.originalReceiptNumber,
    this.returnedLines,
    this.returnCredit,
    this.replacementTotal,
    this.change,
    this.cashierName,
    this.customization = const ReceiptCustomization(),
  });

  final StoreInfo store;
  final String receiptNumber;
  final DateTime createdAt;
  final SaleTotals totals;
  final List<ReceiptLine> lines;
  final List<PaymentDraft> payments;
  final String title;
  final String? originalReceiptNumber;
  final List<ReceiptLine>? returnedLines;
  final double? returnCredit;
  final double? replacementTotal;
  final double? change;
  final String? cashierName;
  final ReceiptCustomization customization;

  bool get isRefund => title.contains('REFUND');
  bool get isExchange => title.contains('EXCHANGE');
}

/// Formats a receipt as plain text. The shop has no printer yet, so this text
/// is shown on screen; a ReceiptService for ESC/POS can consume the same data
/// later without touching the sale flow (§35 “Print Receipt”).
String buildReceiptText({
  required StoreInfo store,
  required String receiptNumber,
  required DateTime createdAt,
  required SaleTotals totals,
  required List<({String name, double quantity, double unitPrice})> lines,
  required List<PaymentDraft> payments,
  double? change,
}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final buffer = StringBuffer()..writeln(store.name);
  if (store.address.isNotEmpty) buffer.writeln(store.address);
  // The contact field may hold several numbers separated by '/'; each prints
  // on its own row so a two-number shop doesn't get one long line.
  for (final phone in phoneLines(store.phone)) {
    buffer.writeln('Tel: $phone');
  }
  buffer
    ..writeln('RECEIPT $receiptNumber')
    ..writeln(
      '${createdAt.year}-${two(createdAt.month)}-${two(createdAt.day)} '
      '${two(createdAt.hour)}:${two(createdAt.minute)}',
    )
    ..writeln('--------------------------------');

  for (final line in lines) {
    buffer.writeln('${line.name} x ${_qty(line.quantity)}');
    buffer.writeln('    ${formatMoney(line.unitPrice * line.quantity)}');
  }
  buffer.writeln('--------------------------------');
  buffer.writeln('Subtotal:  ${formatMoney(totals.grossSubtotal)}');
  if (totals.discount > 0) {
    buffer.writeln('Discount:  -${formatMoney(totals.discount)}');
  }
  buffer.writeln('VAT incl.: ${formatMoney(totals.taxIncluded)}');
  buffer.writeln('TOTAL:     ${formatMoney(totals.total)}');

  for (final payment in payments) {
    buffer.writeln('${payment.method.label}: ${formatMoney(payment.amount)}');
    final reference = payment.reference?.trim() ?? '';
    if (reference.isNotEmpty) buffer.writeln('  Ref: $reference');
  }
  if (change != null && change > 0) {
    buffer.writeln('Change:    ${formatMoney(change)}');
  }
  buffer.writeln('--------------------------------');
  buffer.writeln('Thank you for your purchase!');
  return buffer.toString();
}

String formatMoney(double value) => 'GHS ${value.toStringAsFixed(2)}';

/// Local date+time, e.g. 2026-01-01 14:05.
String formatDateTime(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}

/// Compact quantity label: whole counts without decimals (`4`), half-units
/// with them (`6.5`).
String formatQuantity(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

String _qty(double value) => formatQuantity(value);
