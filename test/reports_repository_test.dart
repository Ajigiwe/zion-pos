import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/reports/data/reports_repository.dart';
import 'package:instrument_pos/features/reports/domain/report_models.dart';
import 'package:uuid/uuid.dart';

void main() {
  late AppDatabase db;
  late ReportsRepository repo;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 10);
  final yesterday = today.subtract(const Duration(days: 1));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ReportsRepository(db);
  });

  tearDown(() => db.close());

  Future<String> addUser(String displayName) async {
    final id = const Uuid().v4();
    await db
        .into(db.users)
        .insert(
          UsersCompanion(
            id: Value(id),
            username: Value(displayName.toLowerCase()),
            displayName: Value(displayName),
            passwordHash: Value('unused'),
            role: Value('CASHIER'),
          ),
        );
    return id;
  }

  Future<String> addProduct(String name) async {
    final id = const Uuid().v4();
    await db
        .into(db.products)
        .insert(
          ProductsCompanion(
            id: Value(id),
            name: Value(name),
            sku: Value('SKU-$name'),
            costPrice: const Value(10),
            sellingPrice: const Value(50),
          ),
        );
    return id;
  }

  Future<String> addSale({
    required DateTime createdAt,
    String? cashierId,
    double subtotal = 0,
    double discount = 0,
    List<(PaymentMethod, double)> payments = const [],
    List<({String productId, double quantity, double unitPrice})> items =
        const [],
  }) async {
    final id = const Uuid().v4();
    final total = subtotal - discount;
    await db
        .into(db.sales)
        .insert(
          SalesCompanion(
            id: Value(id),
            receiptNumber: Value('R-${const Uuid().v4().substring(0, 8)}'),
            cashierId: Value(cashierId),
            subtotal: Value(subtotal),
            discount: Value(discount),
            total: Value(total),
            createdAt: Value(createdAt),
          ),
        );
    for (final (method, amount) in payments) {
      await db
          .into(db.payments)
          .insert(
            PaymentsCompanion(
              id: Value(const Uuid().v4()),
              saleId: Value(id),
              paymentMethod: Value(method),
              amount: Value(amount),
              createdAt: Value(createdAt),
            ),
          );
    }
    for (final item in items) {
      await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion(
              id: Value(const Uuid().v4()),
              saleId: Value(id),
              productId: Value(item.productId),
              quantity: Value(item.quantity),
              unitPrice: Value(item.unitPrice),
              subtotal: Value(item.quantity * item.unitPrice),
            ),
          );
    }
    return id;
  }

  Future<String> addRefund({
    required String saleId,
    required DateTime createdAt,
    required PaymentMethod method,
    required double amount,
    String? cashierId,
    String? reason,
    List<({String productId, double quantity, double unitPrice})> items =
        const [],
  }) async {
    final id = const Uuid().v4();
    await db
        .into(db.refunds)
        .insert(
          RefundsCompanion(
            id: Value(id),
            refundNumber: Value('RF-${const Uuid().v4().substring(0, 8)}'),
            originalSaleId: Value(saleId),
            cashierId: Value(cashierId),
            refundMethod: Value(method),
            amount: Value(amount),
            reason: Value(reason),
            createdAt: Value(createdAt),
          ),
        );
    for (final item in items) {
      await db
          .into(db.refundItems)
          .insert(
            RefundItemsCompanion(
              id: Value(const Uuid().v4()),
              refundId: Value(id),
              saleItemId: Value(const Uuid().v4()),
              productId: Value(item.productId),
              quantity: Value(item.quantity),
              unitPrice: Value(item.unitPrice),
              subtotal: Value(item.quantity * item.unitPrice),
            ),
          );
    }
    return id;
  }

  test('financial reconciliation nets refunds and splits by method', () async {
    await addSale(
      createdAt: today,
      subtotal: 100,
      payments: [(PaymentMethod.cash, 100)],
    );
    await addSale(
      createdAt: today,
      subtotal: 60,
      discount: 10,
      payments: [(PaymentMethod.mobileMoney, 50)],
    );
    // Outside the Today range — must be excluded.
    await addSale(
      createdAt: yesterday,
      subtotal: 999,
      payments: [(PaymentMethod.cash, 999)],
    );

    final range = TimelineRange.today.resolve(now);
    final financial = (await repo.load(range)).financial;

    expect(financial.grossSales, closeTo(150, 0.001));
    expect(financial.discounts, closeTo(10, 0.001));
    expect(financial.saleCount, 2);
    expect(financial.moneyByMethod(PaymentMethod.cash), closeTo(100, 0.001));
    expect(
      financial.moneyByMethod(PaymentMethod.mobileMoney),
      closeTo(50, 0.001),
    );
    expect(financial.paymentsByMethodCount(PaymentMethod.cash), 1);
    expect(financial.refundsTotal, 0);
    expect(financial.netSales, closeTo(150, 0.001));
  });

  test('sales by cashier and by product aggregate the ledger', () async {
    final kofi = await addUser('Kofi');
    final ama = await addUser('Ama');
    final drum = await addProduct('Drum');
    final speaker = await addProduct('Speaker');

    await addSale(
      createdAt: today,
      cashierId: kofi,
      subtotal: 100,
      payments: [(PaymentMethod.cash, 100)],
      items: [(productId: drum, quantity: 2, unitPrice: 50)],
    );
    await addSale(
      createdAt: today,
      cashierId: ama,
      subtotal: 60,
      payments: [(PaymentMethod.mobileMoney, 60)],
      items: [(productId: speaker, quantity: 1, unitPrice: 60)],
    );

    final data = await repo.load(TimelineRange.today.resolve(now));

    expect(data.byCashier.map((r) => r.cashierName).toList(), ['Kofi', 'Ama']);
    expect(data.byCashier.first.saleCount, 1);
    expect(data.byCashier.first.total, closeTo(100, 0.001));

    expect(data.byProduct.map((r) => r.name).toList(), ['Drum', 'Speaker']);
    expect(data.byProduct.first.quantity, closeTo(2, 0.001));
    expect(data.byProduct.first.revenue, closeTo(100, 0.001));
    expect(data.byProduct.first.sku, 'SKU-Drum');
  });

  test('refunds break down by cashier, product and reason', () async {
    final kofi = await addUser('Kofi');
    final drum = await addProduct('Drum');
    final speaker = await addProduct('Speaker');
    final sale = await addSale(createdAt: today, subtotal: 150);

    await addRefund(
      saleId: sale,
      createdAt: today,
      method: PaymentMethod.cash,
      amount: 50,
      cashierId: kofi,
      reason: 'Defective',
      items: [(productId: drum, quantity: 1, unitPrice: 50)],
    );
    await addRefund(
      saleId: sale,
      createdAt: today,
      method: PaymentMethod.mobileMoney,
      amount: 30,
      reason: null,
      items: [(productId: speaker, quantity: 0.5, unitPrice: 60)],
    );
    // Outside the range — excluded.
    await addRefund(
      saleId: sale,
      createdAt: yesterday,
      method: PaymentMethod.cash,
      amount: 999,
      reason: 'Old',
    );

    final data = await repo.load(TimelineRange.today.resolve(now));
    final financial = data.financial;

    expect(financial.refundsTotal, closeTo(80, 0.001));
    expect(financial.refundCount, 2);
    expect(
      financial.refundsByMethodTotal(PaymentMethod.cash),
      closeTo(50, 0.001),
    );
    expect(
      financial.refundsByMethodTotal(PaymentMethod.mobileMoney),
      closeTo(30, 0.001),
    );
    expect(financial.netSales, closeTo(150 - 80, 0.001));

    expect(data.refundsByCashier.map((r) => r.cashierName).toList(), [
      'Kofi',
      'Unknown',
    ]);
    expect(data.refundsByCashier.first.total, closeTo(50, 0.001));
    expect(data.refundsByProduct.map((r) => r.name).toList(), [
      'Drum',
      'Speaker',
    ]);
    expect(data.refundsByProduct.last.quantity, closeTo(0.5, 0.001));

    expect(data.refundReasons.map((r) => r.reason).toList(), [
      'Defective',
      'Not specified',
    ]);
    expect(data.refundReasons.last.count, 1);
  });

  test('wider ranges include older sales and refunds', () async {
    final sale = await addSale(
      createdAt: today,
      subtotal: 100,
      payments: [(PaymentMethod.cash, 100)],
    );
    await addRefund(
      saleId: sale,
      createdAt: yesterday,
      method: PaymentMethod.cash,
      amount: 40,
    );

    final week = await repo.load(TimelineRange.last7Days.resolve(now));
    expect(week.financial.saleCount, 1);
    expect(week.financial.refundsTotal, closeTo(40, 0.001));
    expect(week.financial.netSales, closeTo(60, 0.001));

    final todayData = await repo.load(TimelineRange.today.resolve(now));
    expect(todayData.financial.refundsTotal, 0);
    expect(todayData.isEmpty, isFalse);
  });

  test('empty range reports an empty dataset', () async {
    final data = await repo.load(TimelineRange.today.resolve(now));
    expect(data.isEmpty, isTrue);
    expect(data.byCashier, isEmpty);
    expect(data.byProduct, isEmpty);
    expect(data.refundReasons, isEmpty);
  });
}
