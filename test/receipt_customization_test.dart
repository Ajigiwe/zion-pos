import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/domain/receipt_customization.dart';
import 'package:instrument_pos/features/sales/domain/receipt_document.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';

void main() {
  ReceiptContent sampleContent({ReceiptCustomization? customization}) {
    return ReceiptContent(
      store: const StoreInfo(
        name: 'Acme Supermarket',
        address: '123 Test St',
        phone: '+1 234 567 890',
      ),
      receiptNumber: 'REC-TEST-001',
      createdAt: DateTime(2026, 9, 19, 10, 30),
      cashierName: 'Alice Johnson',
      totals: const SaleTotals(
        grossSubtotal: 80.0,
        discount: 5.0,
        taxIncluded: 10.0,
        total: 85.0,
      ),
      lines: const [
        (name: 'Item Alpha', quantity: 3, unitPrice: 10.0),
        (name: 'Item Beta', quantity: 1, unitPrice: 50.0),
      ],
      payments: const [
        PaymentDraft(method: PaymentMethod.cash, amount: 100.0),
      ],
      change: 15.0,
      customization: customization ?? const ReceiptCustomization(),
    );
  }

  group('ReceiptCustomization & Document Builder Tests', () {
    test('Default customization has all expected defaults', () {
      const config = ReceiptCustomization();
      expect(config.showStoreName, isTrue);
      expect(config.showStoreAddress, isTrue);
      expect(config.showStorePhone, isTrue);
      expect(config.showCashierName, isTrue);
      expect(config.showItemPriceMath, isTrue);
      expect(config.showTax, isTrue);
      expect(config.showDiscount, isTrue);
      expect(config.showPaymentBreakdown, isTrue);
      expect(config.showChangeDue, isTrue);
      expect(config.showBarcode, isTrue);
      expect(config.showCustomerSignature, isFalse);
      expect(config.headerCustomText, contains('Dealers in Quality'));
      expect(config.footerMessage, contains('Thank you for your business'));
      expect(config.paperWidth, '80mm');
      expect(config.sideMargin, 14.0);
      expect(config.bottomFeedSpace, 50.0);
    });

    test('buildReceiptPdf renders successfully with 58mm paper and custom margins', () async {
      const config = ReceiptCustomization(
        paperWidth: '58mm',
        sideMargin: 20.0,
        bottomFeedSpace: 60.0,
      );
      final content = sampleContent(customization: config);
      final pdfBytes = await buildReceiptPdf(content: content);
      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(400));
    });

    test('buildReceiptPdf renders successfully with full customization toggles enabled', () async {
      const config = ReceiptCustomization(
        headerCustomText: 'Quality You Can Trust',
        footerMessage: 'No returns after 30 days.',
        showCustomerSignature: true,
        showBarcode: true,
      );

      final content = ReceiptContent(
        store: const StoreInfo(
          name: 'Acme Supermarket',
          address: '123 Test St',
          phone: '+1 234 567 890',
        ),
        receiptNumber: 'REC-TEST-001',
        createdAt: DateTime(2026, 9, 19, 10, 30),
        cashierName: 'Alice Johnson',
        totals: const SaleTotals(
          grossSubtotal: 80.0,
          discount: 5.0,
          taxIncluded: 10.0,
          total: 85.0,
        ),
        lines: const [
          (name: 'Item Alpha', quantity: 3, unitPrice: 10.0),
          (name: 'Item Beta', quantity: 1, unitPrice: 50.0),
        ],
        payments: const [
          PaymentDraft(method: PaymentMethod.cash, amount: 100.0),
        ],
        change: 15.0,
        customization: config,
      );

      final pdfBytes = await buildReceiptPdf(content: content);
      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(500));
    });

    test('buildReceiptPdf renders cleanly when all optional toggles are hidden', () async {
      const config = ReceiptCustomization(
        showStoreName: false,
        showStoreAddress: false,
        showStorePhone: false,
        headerCustomText: '',
        showCashierName: false,
        showItemPriceMath: false,
        showTax: false,
        showDiscount: false,
        showPaymentBreakdown: false,
        showChangeDue: false,
        footerMessage: '',
        showBarcode: false,
        showCustomerSignature: false,
      );

      final content = ReceiptContent(
        store: const StoreInfo(
          name: 'Acme Supermarket',
          address: '123 Test St',
          phone: '+1 234 567 890',
        ),
        receiptNumber: 'REC-MINIMAL-002',
        createdAt: DateTime(2026, 9, 19, 10, 30),
        cashierName: 'Alice Johnson',
        totals: const SaleTotals(
          grossSubtotal: 20.0,
          discount: 0.0,
          taxIncluded: 0.0,
          total: 20.0,
        ),
        lines: const [
          (name: 'Item Alpha', quantity: 1, unitPrice: 20.0),
        ],
        payments: const [
          PaymentDraft(method: PaymentMethod.mobileMoney, amount: 20.0),
        ],
        change: 0.0,
        customization: config,
      );

      final pdfBytes = await buildReceiptPdf(content: content);
      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(300));
    });
  });
}
