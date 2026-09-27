import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/auth/data/auth_repository.dart';
import 'package:instrument_pos/features/inventory/data/inventory_repository.dart';
import 'package:instrument_pos/features/refunds/data/refunds_repository.dart';
import 'package:instrument_pos/features/refunds/domain/refund_models.dart';
import 'package:instrument_pos/features/sales/data/sales_repository.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<List<AuditLog>> auditRows() async {
    final query = db.select(db.auditLogs)
      ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]);
    return query.get();
  }

  test(
    'sales, refunds, opening stock, adjustments and logins are audited',
    () async {
      final auth = DriftAuthRepository(db);
      final inventory = InventoryRepository(db);
      final sales = DriftSaleRepository(db);
      final refunds = DriftRefundsRepository(db);

      // Login success + failure.
      await auth.authenticate('owner', 'admin123');
      await expectLater(
        auth.authenticate('owner', 'nope'),
        throwsA(isA<AuthException>()),
      );

      // A cashier account is created (USER_CREATE) and used below.
      final cashier = await auth.createUser(
        username: 'ama',
        displayName: 'Ama',
        role: 'CASHIER',
        password: 'secret1',
      );

      // Opening stock + manual adjustment.
      await db
          .into(db.products)
          .insert(
            ProductsCompanion(
              id: const Value('prod-1'),
              sku: const Value('SKU-1'),
              name: const Value('Guitar'),
              costPrice: const Value(0),
              sellingPrice: const Value(5000),
              taxRate: const Value(0),
              trackingType: const Value(ProductTrackingType.quantity),
              isActive: const Value(true),
              createdAt: Value(DateTime(2026, 1, 1)),
              updatedAt: Value(DateTime(2026, 1, 1)),
            ),
          );
      await inventory.recordOpeningStock({'prod-1': 5}, userId: cashier.id);
      await inventory.recordMovement(
        productId: 'prod-1',
        type: MovementType.adjustment,
        quantity: -1,
        reason: 'Physical count',
        userId: cashier.id,
      );

      // Sale + refund by the cashier.
      await sales.completeSale(
        SaleRequest(
          lines: const [(productId: 'prod-1', quantity: 1)],
          payments: const [
            PaymentDraft(method: PaymentMethod.cash, amount: 5000),
          ],
          cashierId: cashier.id,
        ),
      );
      final saleId = (await sales.watchRecentSales().first).first.id;
      final remaining = await refunds.remainingQuantitiesFor(saleId);
      final lineId = remaining.keys.first;
      await refunds.createRefund(
        RefundRequest(
          originalSaleId: saleId,
          lines: [
            ReturnLineRequest(
              saleItemId: lineId,
              productId: 'prod-1',
              quantity: 1,
            ),
          ],
          cashierId: cashier.id,
        ),
      );

      final rows = await auditRows();
      final actions = rows.map((r) => r.action).toList();
      expect(actions, contains('LOGIN'));
      expect(actions, contains('LOGIN_FAILED'));
      expect(actions, contains('USER_CREATE'));
      expect(actions, contains('OPENING_STOCK'));
      expect(actions, contains('STOCK_ADJUSTMENT'));
      expect(actions, contains('SALE'));
      expect(actions, contains('REFUND'));

      // Actor attribution is recorded where a user is known.
      final saleRow = rows.firstWhere((r) => r.action == 'SALE');
      expect(saleRow.userId, cashier.id);
      final openingRows = rows
          .where((r) => r.action == 'OPENING_STOCK')
          .toList();
      expect(openingRows.single.details, contains('1 products, 5 units'));
    },
  );
}
