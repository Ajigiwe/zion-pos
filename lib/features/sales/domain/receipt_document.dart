import 'dart:typed_data';

import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/core/pdf_fonts.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Renders [content] as an 80 mm-wide professional thermal receipt PDF.
/// Features centered store branding, clean tabular items, high-contrast
/// bold totals block, and customer return policy footer.
Future<Uint8List> buildReceiptPdf({required ReceiptContent content}) async {
  final regularFont = await pdfRegularFont();
  final boldFont = await pdfBoldFont();

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
      base: regularFont,
      bold: boldFont,
    ),
  );

  const black = PdfColors.black;
  const darkGrey = PdfColor.fromInt(0xFF333333);

  pw.Text t(
    String text, {
    double size = 9,
    PdfColor color = black,
    pw.FontWeight weight = pw.FontWeight.normal,
    pw.TextAlign align = pw.TextAlign.left,
    double spacing = 0,
    double height = 1.25,
  }) => pw.Text(
    text,
    textAlign: align,
    style: pw.TextStyle(
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: spacing,
      height: height,
    ),
  );

  pw.Widget solidDivider({double width = 0.8, double verticalMargin = 4}) =>
      pw.Container(
        margin: pw.EdgeInsets.symmetric(vertical: verticalMargin),
        decoration: pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: black, width: width)),
        ),
      );

  pw.Widget dashedDivider({double verticalMargin = 4}) => pw.Container(
    margin: pw.EdgeInsets.symmetric(vertical: verticalMargin),
    child: pw.Row(
      children: List.generate(
        36,
        (index) => pw.Expanded(
          child: pw.Container(
            height: 0.8,
            color: index % 2 == 0 ? black : PdfColors.white,
          ),
        ),
      ),
    ),
  );

  pw.Widget totalRow(
    String left,
    String right, {
    bool bold = false,
    double size = 9,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: t(
              left,
              size: size,
              weight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          t(
            right,
            size: size,
            weight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ],
      ),
    );
  }

  final totalItemCount = content.lines.fold<double>(
    0,
    (sum, line) => sum + line.quantity,
  );

  final mmWidth = content.customization.paperWidth == '58mm' ? 58.0 : 80.0;
  final sideMargin = content.customization.sideMargin.clamp(2.0, 36.0);
  final bottomFeed = content.customization.bottomFeedSpace.clamp(10.0, 120.0);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat(
        mmWidth * PdfPageFormat.mm,
        297 * PdfPageFormat.mm,
        marginAll: 0,
      ),
      margin: pw.EdgeInsets.zero,
      build: (context) => [
        pw.Container(
          padding: pw.EdgeInsets.fromLTRB(sideMargin, 8, sideMargin, 8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ------------------------------------ Store Letterhead
              if (content.customization.showStoreName)
                t(
                  content.store.name.toUpperCase(),
                  size: 13,
                  weight: pw.FontWeight.bold,
                  align: pw.TextAlign.center,
                  spacing: 0.5,
                ),
              if (content.customization.showStoreAddress &&
                  content.store.address.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: t(
                    content.store.address,
                    size: 8,
                    color: darkGrey,
                    align: pw.TextAlign.center,
                  ),
                ),
              if (content.customization.showStorePhone)
                for (final phone in phoneLines(content.store.phone))
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 1),
                    child: t(
                      'Tel: $phone',
                      size: 8,
                      color: darkGrey,
                      align: pw.TextAlign.center,
                    ),
                  ),
              if (content.customization.headerCustomText.trim().isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: t(
                    content.customization.headerCustomText.trim(),
                    size: 7.5,
                    color: darkGrey,
                    align: pw.TextAlign.center,
                  ),
                ),

              solidDivider(width: 1.2, verticalMargin: 6),

              // ------------------------------------ Receipt Meta
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  t(
                    '${content.title}: ${content.receiptNumber}',
                    size: 9,
                    weight: pw.FontWeight.bold,
                  ),
                  t(formatDateTime(content.createdAt), size: 8, color: darkGrey),
                ],
              ),
              if (content.originalReceiptNumber != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 1),
                  child: t(
                    'Original Sale: ${content.originalReceiptNumber}',
                    size: 8,
                    weight: pw.FontWeight.bold,
                    color: darkGrey,
                  ),
                ),
              if (content.customization.showCashierName &&
                  (content.cashierName?.trim().isNotEmpty ?? false))
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: t(
                    'Cashier: ${content.cashierName!.trim()}',
                    size: 8,
                    color: darkGrey,
                  ),
                ),

              dashedDivider(verticalMargin: 5),

              // ------------------------------------ Returned Items (If present)
              if (content.returnedLines != null &&
                  content.returnedLines!.isNotEmpty) ...[
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: t(
                    'RETURNED ITEMS',
                    size: 7.5,
                    weight: pw.FontWeight.bold,
                  ),
                ),
                for (final line in content.returnedLines!) ...[
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.SizedBox(
                          width: 24,
                          child: t(
                            '${formatQuantity(line.quantity)}x',
                            size: 9,
                            weight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Expanded(
                          child: t(line.name, size: 9, weight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(width: 6),
                        t(
                          '-${formatMoney(line.unitPrice * line.quantity)}',
                          size: 9,
                          weight: pw.FontWeight.bold,
                        ),
                      ],
                    ),
                  ),
                ],
                dashedDivider(verticalMargin: 4),
              ],

              // ------------------------------------ Purchased / Replacement Items
              if (content.lines.isNotEmpty) ...[
                if (content.isExchange)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: t(
                      'REPLACEMENT ITEMS',
                      size: 7.5,
                      weight: pw.FontWeight.bold,
                    ),
                  ),
                pw.Row(
                  children: [
                    pw.SizedBox(
                      width: 24,
                      child: t('QTY', size: 7.5, weight: pw.FontWeight.bold),
                    ),
                    pw.Expanded(
                      child: t(
                        'ITEM DESCRIPTION',
                        size: 7.5,
                        weight: pw.FontWeight.bold,
                      ),
                    ),
                    t('AMOUNT', size: 7.5, weight: pw.FontWeight.bold),
                  ],
                ),
                solidDivider(width: 0.6, verticalMargin: 3),
                for (final line in content.lines) ...[
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.SizedBox(
                          width: 24,
                          child: t(
                            '${formatQuantity(line.quantity)}x',
                            size: 9,
                            weight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              t(line.name, size: 9, weight: pw.FontWeight.bold),
                              if (content.customization.showItemPriceMath &&
                                  line.quantity > 1)
                                t(
                                  '@ ${formatMoney(line.unitPrice)} each',
                                  size: 7.5,
                                  color: darkGrey,
                                ),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        t(
                          formatMoney(line.unitPrice * line.quantity),
                          size: 9,
                          weight: pw.FontWeight.bold,
                        ),
                      ],
                    ),
                  ),
                ],
                solidDivider(width: 0.6, verticalMargin: 4),
              ],

              // ------------------------------------ Totals & Settlement
              if (content.isExchange) ...[
                totalRow(
                  'Replacement Total',
                  formatMoney(content.replacementTotal ?? content.totals.total),
                ),
                totalRow(
                  'Less Return Credit',
                  '-${formatMoney(content.returnCredit ?? 0)}',
                ),
                solidDivider(width: 1.5, verticalMargin: 4),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      t(
                        content.totals.total == 0
                            ? 'EVEN EXCHANGE'
                            : (content.payments.any((p) => p.amount > 0)
                                ? 'NET BALANCE DUE'
                                : 'NET CASH REFUND'),
                        size: 11,
                        weight: pw.FontWeight.bold,
                        spacing: 0.5,
                      ),
                      t(
                        formatMoney(content.totals.total),
                        size: 12,
                        weight: pw.FontWeight.bold,
                      ),
                    ],
                  ),
                ),
                solidDivider(width: 1.5, verticalMargin: 4),
              ] else if (content.isRefund) ...[
                solidDivider(width: 1.5, verticalMargin: 4),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      t(
                        'TOTAL REFUNDED',
                        size: 11,
                        weight: pw.FontWeight.bold,
                        spacing: 0.5,
                      ),
                      t(
                        formatMoney(content.totals.total),
                        size: 12,
                        weight: pw.FontWeight.bold,
                      ),
                    ],
                  ),
                ),
                solidDivider(width: 1.5, verticalMargin: 4),
              ] else ...[
                totalRow('Subtotal', formatMoney(content.totals.grossSubtotal)),
                if (content.customization.showDiscount &&
                    content.totals.discount > 0)
                  totalRow(
                    'Discount',
                    '-${formatMoney(content.totals.discount)}',
                  ),
                if (content.customization.showTax &&
                    content.totals.taxIncluded > 0)
                  totalRow(
                    'VAT (15% Included)',
                    formatMoney(content.totals.taxIncluded),
                    size: 8,
                  ),
                solidDivider(width: 1.5, verticalMargin: 4),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      t(
                        'TOTAL DUE',
                        size: 12,
                        weight: pw.FontWeight.bold,
                        spacing: 0.5,
                      ),
                      t(
                        formatMoney(content.totals.total),
                        size: 12,
                        weight: pw.FontWeight.bold,
                      ),
                    ],
                  ),
                ),
                solidDivider(width: 1.5, verticalMargin: 4),
              ],

              // ------------------------------------ Payments & Change
              if (content.customization.showPaymentBreakdown)
                for (final payment in content.payments) ...[
                  totalRow(
                    'Paid (${payment.method.label})',
                    formatMoney(payment.amount),
                    bold: payment.method == PaymentMethod.cash,
                  ),
                  if ((payment.reference ?? '').trim().isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 6, bottom: 2),
                      child: t(
                        'Ref: ${payment.reference!.trim()}',
                        size: 7.5,
                        color: darkGrey,
                      ),
                    ),
                ],
              if (content.customization.showChangeDue &&
                  content.change != null &&
                  content.change! > 0)
                totalRow(
                  'CHANGE DUE',
                  formatMoney(content.change!),
                  bold: true,
                  size: 9.5,
                ),

              dashedDivider(verticalMargin: 6),

              // ------------------------------------ Footer Notes & Barcode
              t(
                'Total Items: ${formatQuantity(totalItemCount)}',
                size: 8,
                color: darkGrey,
                align: pw.TextAlign.center,
              ),
              if (content.customization.footerMessage.trim().isNotEmpty) ...[
                pw.SizedBox(height: 4),
                for (final msgLine in content.customization.footerMessage
                    .trim()
                    .split('\n'))
                  t(
                    msgLine.trim(),
                    size: 7.5,
                    color: darkGrey,
                    align: pw.TextAlign.center,
                  ),
              ],
              if (content.customization.showCustomerSignature) ...[
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    t('Customer Signature:', size: 7.5, color: darkGrey),
                    pw.Container(
                      width: 110,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: darkGrey,
                            width: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (content.customization.showBarcode) ...[
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: content.receiptNumber,
                    width: mmWidth == 58.0 ? 120 : 150,
                    height: 30,
                    drawText: true,
                    textStyle: pw.TextStyle(font: regularFont, fontSize: 8),
                  ),
                ),
              ],
              dashedDivider(verticalMargin: 6),
              // Configurable trailing paper feed space so the barcode and bottom
              // divider advance fully past the printer's physical tear bar / cutter.
              pw.SizedBox(height: bottomFeed),
            ],
          ),
        ),
      ],
    ),
  );
  return doc.save();
}
