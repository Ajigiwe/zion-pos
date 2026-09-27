import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';

void main() {
  const totals = SaleTotals(
    grossSubtotal: 5800,
    discount: 0,
    taxIncluded: 0,
    total: 5800,
  );

  String build(StoreInfo store) => buildReceiptText(
    store: store,
    receiptNumber: 'SA-00001',
    createdAt: DateTime(2026, 1, 1, 10, 0),
    totals: totals,
    lines: const [],
    payments: const [],
  );

  test(
    'letterhead prints name, address and phone above the receipt number',
    () {
      final text = build(kStoreInfo);
      expect(
        text,
        contains(
          'Zion Musical Centre\n'
          'Market Circle - Tarkwa\n'
          'Tel: 054 171 7773\n'
          'Tel: 0275439830\n'
          'RECEIPT SA-00001',
        ),
      );
    },
  );

  test('several contact numbers print on separate Tel lines', () {
    const store = StoreInfo(
      name: 'Zion Musical Centre',
      address: '',
      phone: '054 171 7773 / 0275439830',
    );
    final text = build(store);
    expect(text, contains('Tel: 054 171 7773\nTel: 0275439830\n'));
    // No separator-slash leaks into the letterhead.
    expect(text, isNot(contains('/ 027')));
  });

  test('blank address and phone lines are omitted from the letterhead', () {
    const store = StoreInfo(
      name: 'Zion Musical Centre',
      address: '',
      phone: '',
    );
    final text = build(store);
    expect(text, contains('Zion Musical Centre\nRECEIPT SA-00001'));
    expect(text, isNot(contains('Tel:')));
  });

  test('mobile money reference prints under the payment line', () {
    final text = buildReceiptText(
      store: kStoreInfo,
      receiptNumber: 'SA-00002',
      createdAt: DateTime(2026, 1, 1, 10, 1),
      totals: totals,
      lines: const [],
      payments: const [
        PaymentDraft(
          method: PaymentMethod.mobileMoney,
          amount: 5800,
          reference: '0240123456',
        ),
      ],
    );
    expect(text, contains('Mobile Money: GHS 5800.00'));
    expect(text, contains('  Ref: 0240123456'));
  });

  test('cash payments never print a reference line', () {
    final text = buildReceiptText(
      store: kStoreInfo,
      receiptNumber: 'SA-00003',
      createdAt: DateTime(2026, 1, 1, 10, 2),
      totals: totals,
      lines: const [],
      payments: const [PaymentDraft(method: PaymentMethod.cash, amount: 5800)],
    );
    expect(text, contains('Cash: GHS 5800.00'));
    expect(text, isNot(contains('Ref:')));
  });
}
