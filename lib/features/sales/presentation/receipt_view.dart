import 'package:flutter/material.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';

/// A slim, modern paper-look receipt: centered uppercase letterhead, clean
/// divider rules, column-aligned item lines, high-contrast totals block, and
/// return policy footer.
class ReceiptView extends StatelessWidget {
  const ReceiptView({super.key, required this.content});

  final ReceiptContent content;

  static const double paperWidth = 320;

  @override
  Widget build(BuildContext context) {
    final store = content.store;
    final totals = content.totals;
    const ink = Color(0xFF1B1B1F);
    const darkGrey = Color(0xFF424242);
    const lightGrey = Color(0xFF757575);

    Widget lineRow(
      String left,
      String right, {
      bool bold = false,
      double size = 12.5,
      Color color = ink,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                left,
                style: TextStyle(
                  fontSize: size,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
            Text(
              right,
              style: TextStyle(
                fontSize: size,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    final totalItemCount = content.lines.fold<double>(
      0,
      (sum, line) => sum + line.quantity,
    );

    final custom = content.customization;
    final viewWidth = custom.paperWidth == '58mm' ? 240.0 : 320.0;
    final sidePadding = custom.sideMargin.clamp(4.0, 32.0);

    return Container(
      width: viewWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(sidePadding, 18, sidePadding, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ------------------------------------ Letterhead
          if (custom.showStoreName)
            Text(
              store.name.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: ink,
                letterSpacing: 0.5,
              ),
            ),
          if (custom.showStoreAddress && store.address.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                store.address,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: darkGrey),
              ),
            ),
          if (custom.showStorePhone)
            for (final phone in phoneLines(store.phone))
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  'Tel: $phone',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: darkGrey),
                ),
              ),
          if (custom.headerCustomText.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                custom.headerCustomText.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5, color: darkGrey),
              ),
            ),
          const SizedBox(height: 10),
          const Divider(height: 2, thickness: 1.5, color: ink),
          const SizedBox(height: 6),

          // ------------------------------------ Receipt Meta
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${content.title}: ${content.receiptNumber}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              Text(
                formatDateTime(content.createdAt),
                style: const TextStyle(fontSize: 11, color: lightGrey),
              ),
            ],
          ),
          if (content.originalReceiptNumber != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Original Sale: ${content.originalReceiptNumber}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: darkGrey,
                ),
              ),
            ),
          if (custom.showCashierName &&
              (content.cashierName?.trim().isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'Cashier: ${content.cashierName!.trim()}',
                style: const TextStyle(fontSize: 11, color: darkGrey),
              ),
            ),
          const SizedBox(height: 6),
          const _DashedDivider(),
          const SizedBox(height: 4),

          // ------------------------------------ Returned Items (If present)
          if (content.returnedLines != null &&
              content.returnedLines!.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'RETURNED ITEMS',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.redAccent,
                ),
              ),
            ),
            for (final line in content.returnedLines!) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${formatQuantity(line.quantity)}x',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        line.name,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '-${formatMoney(line.unitPrice * line.quantity)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            const _DashedDivider(),
            const SizedBox(height: 4),
          ],

          // ------------------------------------ Purchased / Replacement Items
          if (content.lines.isNotEmpty) ...[
            if (content.isExchange)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'REPLACEMENT ITEMS',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
            const Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    'QTY',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'ITEM DESCRIPTION',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
                Text(
                  'AMOUNT',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            const Divider(height: 1, thickness: 1, color: ink),
            const SizedBox(height: 4),
            for (final line in content.lines) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${formatQuantity(line.quantity)}x',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.name,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                          if (custom.showItemPriceMath && line.quantity > 1)
                            Text(
                              '@ ${formatMoney(line.unitPrice)} each',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: darkGrey,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatMoney(line.unitPrice * line.quantity),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            const Divider(height: 1, thickness: 1, color: ink),
            const SizedBox(height: 6),
          ],

          // ------------------------------------ Totals & Financial Settlement
          if (content.isExchange) ...[
            lineRow(
              'Replacement Total',
              formatMoney(content.replacementTotal ?? totals.total),
            ),
            lineRow(
              'Less Return Credit',
              '-${formatMoney(content.returnCredit ?? 0)}',
              color: Colors.red.shade700,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              decoration: const BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: ink, width: 2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    totals.total == 0
                        ? 'EVEN EXCHANGE'
                        : (content.payments.any((p) => p.amount > 0)
                            ? 'NET BALANCE DUE'
                            : 'NET CASH REFUND'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: ink,
                    ),
                  ),
                  Text(
                    formatMoney(totals.total),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (content.isRefund) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              decoration: const BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: ink, width: 2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL REFUNDED',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: ink,
                    ),
                  ),
                  Text(
                    formatMoney(totals.total),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            lineRow('Subtotal', formatMoney(totals.grossSubtotal)),
            if (custom.showDiscount && totals.discount > 0)
              lineRow(
                'Discount',
                '-${formatMoney(totals.discount)}',
                color: Colors.red.shade700,
              ),
            if (custom.showTax && totals.taxIncluded > 0)
              lineRow(
                'VAT (15% Included)',
                formatMoney(totals.taxIncluded),
                size: 11,
                color: darkGrey,
              ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              decoration: const BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: ink, width: 2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL DUE',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: ink,
                    ),
                  ),
                  Text(
                    formatMoney(totals.total),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),

          // ------------------------------------ Payments & Change
          if (custom.showPaymentBreakdown)
            for (final payment in content.payments) ...[
              lineRow(
                'Paid (${payment.method.label})',
                formatMoney(payment.amount),
                bold: payment.method == PaymentMethod.cash,
              ),
              if ((payment.reference ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Text(
                    'Ref: ${payment.reference!.trim()}',
                    style: const TextStyle(fontSize: 10.5, color: darkGrey),
                  ),
                ),
            ],
          if (custom.showChangeDue &&
              content.change != null &&
              content.change! > 0)
            lineRow(
              'CHANGE DUE',
              formatMoney(content.change!),
              bold: true,
              size: 13,
              color: const Color(0xFF1B5E20),
            ),
          const SizedBox(height: 8),
          const _DashedDivider(),
          const SizedBox(height: 8),

          // ------------------------------------ Footer & Extras
          Text(
            'Total Items: ${formatQuantity(totalItemCount)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: darkGrey),
          ),
          if (custom.footerMessage.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final msgLine in custom.footerMessage.trim().split('\n'))
              Text(
                msgLine.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5, color: darkGrey),
              ),
          ],
          if (custom.showCustomerSignature) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Customer Signature:',
                  style: TextStyle(fontSize: 10.5, color: darkGrey),
                ),
                Container(
                  width: 120,
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: darkGrey, width: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (custom.showBarcode) ...[
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '||||| |||| |||||| |||| ||||| |||||',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 2,
                        color: ink.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      content.receiptNumber,
                      style: const TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 1,
                        color: darkGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const _DashedDivider(),
        ],
      ),
    );
  }
}

/// A thin horizontal rule of dashes, the classic thermal-receipt divider.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: CustomPaint(
        painter: _DashPainter(color: Colors.black87),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 3.0;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      final end = (x + dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => oldDelegate.color != color;
}
