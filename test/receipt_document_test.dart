import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/domain/receipt_document.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReceiptContent sampleContent({List<ReceiptLine>? lines}) {
    return ReceiptContent(
      store: kStoreInfo,
      receiptNumber: 'SA-00001',
      createdAt: DateTime(2026, 9, 5, 10, 32),
      totals: const SaleTotals(
        grossSubtotal: 760,
        discount: 0,
        taxIncluded: 0,
        total: 760,
      ),
      lines:
          lines ??
          [(name: '10" Evans Double Velum', quantity: 1, unitPrice: 760)],
      payments: const [PaymentDraft(method: PaymentMethod.cash, amount: 800)],
      change: 40,
    );
  }

  test('produces a valid 80mm receipt PDF with Unicode names', () async {
    final bytes = await buildReceiptPdf(content: sampleContent());

    expect(bytes, isA<Uint8List>());
    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('wraps long receipts onto multiple pages without failing', () async {
    final content = sampleContent(
      lines: [
        for (var i = 0; i < 60; i++)
          (name: 'Item ${'x' * 40} — unit $i', quantity: 1, unitPrice: 10.0),
      ],
    );
    final bytes = await buildReceiptPdf(content: content);

    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('handles an empty receipt without crashing', () async {
    final content = ReceiptContent(
      store: kStoreInfo,
      receiptNumber: 'SA-00000',
      createdAt: DateTime(2026, 9, 5),
      totals: const SaleTotals(
        grossSubtotal: 0,
        discount: 0,
        taxIncluded: 0,
        total: 0,
      ),
      lines: const [],
      payments: const [],
    );
    final bytes = await buildReceiptPdf(content: content);
    expect(bytes.length, greaterThan(200));
  });
}
