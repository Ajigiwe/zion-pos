import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/dashboard/data/dashboard_repository.dart';
import 'package:uuid/uuid.dart';

void main() {
  late AppDatabase db;
  late DashboardRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DashboardRepository(db);
  });

  tearDown(() => db.close());

  Future<String> addProduct({
    required String name,
    double reorderLevel = 0,
    double openingStock = 0,
    bool active = true,
  }) async {
    final id = const Uuid().v4();
    await db
        .into(db.products)
        .insert(
          ProductsCompanion(
            id: Value(id),
            name: Value(name),
            sku: Value('SKU-$id'),
            costPrice: const Value(10),
            sellingPrice: const Value(20),
            reorderLevel: Value(reorderLevel),
            isActive: Value(active),
          ),
        );
    if (openingStock > 0) {
      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion(
              id: Value(const Uuid().v4()),
              productId: Value(id),
              movementType: Value(MovementType.openingStock),
              quantity: Value(openingStock),
            ),
          );
    }
    return id;
  }

  Future<void> addSale({
    required String id,
    required String receipt,
    required DateTime createdAt,
    required List<(PaymentMethod, double)> payments,
  }) async {
    final total = payments.fold<double>(0, (sum, p) => sum + p.$2);
    await db
        .into(db.sales)
        .insert(
          SalesCompanion(
            id: Value(id),
            receiptNumber: Value(receipt),
            subtotal: Value(total),
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
  }

  Future<void> addRefund({
    required double amount,
    required PaymentMethod method,
    required DateTime createdAt,
    required String originalSaleId,
  }) async {
    await db
        .into(db.refunds)
        .insert(
          RefundsCompanion(
            id: Value(const Uuid().v4()),
            refundNumber: Value('RF-${const Uuid().v4().substring(0, 6)}'),
            originalSaleId: Value(originalSaleId),
            refundMethod: Value(method),
            amount: Value(amount),
            createdAt: Value(createdAt),
          ),
        );
  }

  test('aggregates today-only sales net of refunds and flags low stock', () async {
    await addProduct(name: 'Drum Head', reorderLevel: 5, openingStock: 5);
    await addProduct(name: 'Speaker', reorderLevel: 5, openingStock: 10);
    await addProduct(name: 'Battery', reorderLevel: 0, openingStock: 0);
    final hidden = await addProduct(
      name: 'Hidden low',
      reorderLevel: 9,
      openingStock: 1,
      active: false,
    );
    expect(hidden, isNotEmpty);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);
    final yesterday = today.subtract(const Duration(days: 1));

    await addSale(
      id: 's-today-1',
      receipt: 'R-1',
      createdAt: today,
      payments: [(PaymentMethod.cash, 100)],
    );
    await addSale(
      id: 's-today-2',
      receipt: 'R-2',
      createdAt: today,
      payments: [(PaymentMethod.mobileMoney, 50), (PaymentMethod.cash, 40)],
    );
    // Yesterday's sale must not count towards today.
    await addSale(
      id: 's-yesterday',
      receipt: 'R-3',
      createdAt: yesterday,
      payments: [(PaymentMethod.cash, 999)],
    );

    await addRefund(
      amount: 10,
      method: PaymentMethod.cash,
      createdAt: today,
      originalSaleId: 's-today-1',
    );
    await addRefund(
      amount: 5,
      method: PaymentMethod.mobileMoney,
      createdAt: today,
      originalSaleId: 's-today-2',
    );
    // Yesterday's refund must not count towards today.
    await addRefund(
      amount: 999,
      method: PaymentMethod.mobileMoney,
      createdAt: yesterday,
      originalSaleId: 's-yesterday',
    );

    final snapshot = await repo.load();

    expect(snapshot.cashTotal, closeTo(130, 0.001)); // 140 paid − 10 refunded
    expect(
      snapshot.mobileMoneyTotal,
      closeTo(45, 0.001),
    ); // 50 paid − 5 refunded
    expect(snapshot.cashPayments, 2);
    expect(snapshot.mobileMoneyPayments, 1);
    expect(snapshot.cashRefunds, closeTo(10, 0.001));
    expect(snapshot.cashRefundCount, 1);
    expect(snapshot.mobileMoneyRefunds, closeTo(5, 0.001));
    expect(snapshot.mobileMoneyRefundCount, 1);
    expect(snapshot.saleCount, 2, reason: 'yesterday is excluded');
    expect(snapshot.takingsTotal, closeTo(175, 0.001));

    // Scarcest first: out-of-stock Battery (0) before Drum Head (5 = reorder).
    expect(snapshot.lowStock.map((p) => p.name).toList(), [
      'Battery',
      'Drum Head',
    ]);
    final battery = snapshot.lowStock.first;
    expect(battery.isOutOfStock, isTrue);
    expect(battery.stock, 0);
    expect(snapshot.lowStock.any((p) => p.name == 'Speaker'), isFalse);
    expect(snapshot.lowStock.any((p) => p.name == 'Hidden low'), isFalse);
  });

  test('empty day reports zeros and no alerts', () async {
    await addProduct(name: 'Speaker', reorderLevel: 5, openingStock: 10);

    final snapshot = await repo.load();

    expect(snapshot.takingsTotal, 0);
    expect(snapshot.cashTotal, 0);
    expect(snapshot.mobileMoneyTotal, 0);
    expect(snapshot.cashRefunds, 0);
    expect(snapshot.mobileMoneyRefunds, 0);
    expect(snapshot.cashRefundCount, 0);
    expect(snapshot.mobileMoneyRefundCount, 0);
    expect(snapshot.saleCount, 0);
    expect(snapshot.lowStock, isEmpty);
  });

  test('products without a reorder level use the global threshold', () async {
    await addProduct(name: 'No level low', reorderLevel: 0, openingStock: 3);
    await addProduct(name: 'No level fine', reorderLevel: 0, openingStock: 8);
    // Own level governs: 3 units is above its own level of 2, so no alert
    // even though 3 is below the global default of 5.
    await addProduct(name: 'Own level fine', reorderLevel: 2, openingStock: 3);

    final snapshot = await repo.load();

    final names = snapshot.lowStock.map((p) => p.name).toSet();
    expect(names, contains('No level low'));
    expect(names, isNot(contains('No level fine')));
    expect(names, isNot(contains('Own level fine')));

    final low = snapshot.lowStock.firstWhere((p) => p.name == 'No level low');
    expect(low.reorderLevel, kDefaultLowStockThreshold);
  });

  test('a saved threshold other than the default is honored', () async {
    await (db.into(db.settings)).insert(
      SettingsCompanion(
        key: const Value(StoreSettingKeys.lowStockThreshold),
        value: const Value('12'),
      ),
    );
    await addProduct(name: 'Custom', reorderLevel: 0, openingStock: 10);

    final snapshot = await repo.load();

    expect(snapshot.lowStock.map((p) => p.name), ['Custom']);
    expect(snapshot.lowStock.single.reorderLevel, 12);
  });
}
