import 'dart:typed_data';

import 'package:instrument_pos/core/pdf_fonts.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a printable stock-count sheet in the store's own sheet layout:
/// numbered rows of `# | ITEM NAME | PRICE (GHC) | QTY` with black borders,
/// the store letterhead up top and Counted by / Checked by lines at the foot.
/// Tables that exceed one page split across pages with the header repeated.
Future<Uint8List> buildStockSheetPdf({
  required StoreInfo store,
  required List<ProductWithStock> products,
  required DateTime now,
}) async {
  final sorted = [...products]
    ..sort(
      (a, b) =>
          a.product.name.toLowerCase().compareTo(b.product.name.toLowerCase()),
    );

  String formatQty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);

  String two(int n) => n.toString().padLeft(2, '0');
  final dateLabel = '${now.year}-${two(now.month)}-${two(now.day)}';

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
      base: await pdfRegularFont(),
      bold: await pdfBoldFont(),
    ),
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            store.name,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          if (store.address.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                store.address,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ),
          // Each contact number prints on its own row (the field may hold
          // several separated by '/').
          for (final phone in phoneLines(store.phone))
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                'Tel: $phone',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10, bottom: 8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'STOCK COUNT SHEET',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(dateLabel, style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
      footer: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Counted by: _______________________',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Checked by: _______________________',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ],
      ),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headers: const ['#', 'ITEM NAME', 'PRICE (GHC)', 'QTY'],
          data: [
            for (var i = 0; i < sorted.length; i++) ...[
              [
                '${i + 1}',
                sorted[i].product.name,
                sorted[i].product.sellingPrice.toStringAsFixed(2),
                formatQty(sorted[i].stock),
              ],
            ],
          ],
          headerStyle: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9.5),
          cellAlignments: {
            0: pw.Alignment.centerRight,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.7),
          columnWidths: {
            0: const pw.FixedColumnWidth(26),
            2: const pw.FixedColumnWidth(70),
            3: const pw.FixedColumnWidth(54),
          },
        ),
        if (sorted.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'No products in the catalog yet.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ),
      ],
    ),
  );
  return doc.save();
}
