import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/inventory/data/inventory_repository.dart';
import 'package:instrument_pos/features/refunds/data/refunds_repository.dart';
import 'package:instrument_pos/features/refunds/domain/refund_models.dart';
import 'package:instrument_pos/features/sales/data/sales_repository.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';

Future<Product> _addProduct(AppDatabase db, String name, double price) async {
  final id = 'prod-${name.toLowerCase().replaceAll(' ', '-')}';
  await db
      .into(db.products)
      .insert(
        ProductsCompanion(
          id: Value(id),
          sku: Value('SKU-$name'),
          name: Value(name),
          costPrice: const Value(0),
          sellingPrice: Value(price),
          taxRate: const Value(0),
          trackingType: Value(ProductTrackingType.quantity),
          isActive: const Value(true),
          createdAt: Value(DateTime(2026, 1, 1)),
          updatedAt: Value(DateTime(2026, 1, 1)),
        ),
      );
  return (db.select(db.products)..where((p) => p.id.equals(id))).getSingle();
}

Future<double> _balance(AppDatabase db, String productId) async {
  final query = db.selectOnly(db.stockMovements)
    ..addColumns([db.stockMovements.quantity.sum()])
    ..where(db.stockMovements.productId.equals(productId));
  final row = await query.getSingle();
  return row.read(db.stockMovements.quantity.sum()) ?? 0;
}

void main() {
  late AppDatabase db;
  late InventoryRepository inventory;
  late DriftSaleRepository sales;
  late DriftRefundsRepository refunds;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventory = InventoryRepository(db);
    sales = DriftSaleRepository(db);
    refunds = DriftRefundsRepository(db);
  });

  tearDown(() => db.close());

  Future<void> seed() async {
    await _addProduct(db, 'Keyboard', 5800);
    await _addProduct(db, 'Speaker', 6000);
    await inventory.recordOpeningStock({
      'prod-keyboard': 10,
      'prod-speaker': 10,
    });
  }

  Future<CompletedSale> sellKeyboard2() async {
    return sales.completeSale(
      const SaleRequest(
        lines: [(productId: 'prod-keyboard', quantity: 2)],
        payments: [PaymentDraft(method: PaymentMethod.cash, amount: 11600)],
      ),
    );
  }

  test('refund returns stock and guards against over-refunding', () async {
    await seed();
    final sale = await sellKeyboard2();
    final saleId = (await sales.watchRecentSales().first).first.id;
    expect(await _balance(db, 'prod-keyboard'), 8);

    final remaining = await refunds.remainingQuantitiesFor(saleId);
    final lineId = remaining.keys.first;
    expect(remaining[lineId], 2);

    final result = await refunds.createRefund(
      RefundRequest(
        originalSaleId: saleId,
        cashierId: 'u-cashier',
        method: PaymentMethod.cash,
        lines: [
          ReturnLineRequest(
            saleItemId: lineId,
            productId: 'prod-keyboard',
            quantity: 1,
          ),
        ],
      ),
    );
    expect(result.refundNumber, 'RF-00001');
    expect(result.amount, closeTo(5800, 0.001));
    expect(await _balance(db, 'prod-keyboard'), 9);

    // One more refund is still allowed; a third unit is not.
    final left = await refunds.remainingQuantitiesFor(saleId);
    expect(left[lineId], 1);
    expect(
      () => refunds.createRefund(
        RefundRequest(
          originalSaleId: saleId,
          lines: [
            ReturnLineRequest(
              saleItemId: lineId,
              productId: 'prod-keyboard',
              quantity: 2,
            ),
          ],
        ),
      ),
      throwsA(isA<RefundException>()),
    );

    // The original sale is untouched and sale history unchanged.
    final detail = await sales.loadSaleDetail(saleId);
    expect(detail.sale.total, closeTo(11600, 0.001));
    expect(detail.sale.paymentStatus, 'PAID');
    expect(sale.receiptNumber, 'SA-00001');
  });

  test(
    'exchange returns stock, sells the replacement and links records',
    () async {
      await seed();
      await sellKeyboard2();
      final originalSaleId = (await sales.watchRecentSales().first).first.id;
      final remaining = await refunds.remainingQuantitiesFor(originalSaleId);
      final keyboardLineId = remaining.keys.first;
      // Return one of the two keyboards in exchange for a speaker.
      final exchange = await refunds.createExchange(
        ExchangeRequest(
          originalSaleId: originalSaleId,
          returnedLines: [
            ReturnLineRequest(
              saleItemId: keyboardLineId,
              productId: 'prod-keyboard',
              quantity: 1,
            ),
          ],
          replacements: const [(productId: 'prod-speaker', quantity: 1)],
          balancePayments: [
            PaymentDraft(method: PaymentMethod.cash, amount: 200),
          ],
          cashierId: 'u-cashier',
        ),
      );
      expect(exchange.exchangeNumber, 'EX-00001');
      expect(exchange.returnCredit, closeTo(5800, 0.001));
      expect(exchange.replacementTotal, closeTo(6000, 0.001));
      expect(exchange.cashBack, 0);

      // Ledger: keyboard back to 9, speaker down to 9.
      expect(await _balance(db, 'prod-keyboard'), 9);
      expect(await _balance(db, 'prod-speaker'), 9);

      // The replacement sale exists with exchange-credit + cash payments.
      final allSales = await sales.watchRecentSales().first;
      expect(allSales.map((s) => s.receiptNumber).toSet(), {
        'SA-00001',
        'SA-00002',
      });
      final replacementSale = allSales.firstWhere((s) => s.total == 6000);
      final detail = await sales.loadSaleDetail(replacementSale.id);
      expect(detail.sale.total, closeTo(6000, 0.001));
      final methods = detail.payments.map((p) => p.paymentMethod).toSet();
      expect(methods, contains(PaymentMethod.exchangeCredit));
      expect(methods, contains(PaymentMethod.cash));

      // Exchange record is linked; the original keyboard line is exhausted.
      final exchanges = await refunds.watchExchanges().first;
      expect(exchanges, hasLength(1));
      final left = await refunds.remainingQuantitiesFor(originalSaleId);
      expect(left[keyboardLineId], 1); // one keyboard still refundable

      // Bad balance: too little paid is refused.
      expect(
        () => refunds.createExchange(
          ExchangeRequest(
            originalSaleId: originalSaleId,
            returnedLines: [
              ReturnLineRequest(
                saleItemId: keyboardLineId,
                productId: 'prod-keyboard',
                quantity: 1,
              ),
            ],
            replacements: const [(productId: 'prod-speaker', quantity: 2)],
            balancePayments: [
              PaymentDraft(method: PaymentMethod.cash, amount: 100),
            ],
          ),
        ),
        throwsA(isA<RefundException>()),
      );
    },
  );

  test('exchange breakdown math is pure and correct', () {
    // Cheaper replacement -> cash back.
    final back = computeExchangeBreakdown(
      returnCredit: 5800,
      replacementTotal: 4000,
    );
    expect(back.balanceDue, 0);
    expect(back.cashBack, closeTo(1800, 0.001));
    expect(back.exchangeCredit, closeTo(4000, 0.001));

    // Pricier replacement -> balance due.
    final due = computeExchangeBreakdown(
      returnCredit: 5800,
      replacementTotal: 7000,
    );
    expect(due.balanceDue, closeTo(1200, 0.001));
    expect(due.cashBack, 0);
    expect(due.exchangeCredit, closeTo(5800, 0.001));
  });
}
