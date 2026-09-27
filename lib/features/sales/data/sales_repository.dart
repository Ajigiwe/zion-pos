import 'package:drift/drift.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/lan_sync_service.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/core/database/workstation_config.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';
import 'package:uuid/uuid.dart';

/// A sale to record: products+quantities chosen by the cashier plus payments.
class SaleRequest {
  const SaleRequest({
    required this.lines,
    required this.payments,
    this.discount = 0,
    this.cashierId,
  });

  final List<({String productId, double quantity})> lines;
  final List<PaymentDraft> payments;
  final double discount;

  /// Signed-in cashier recorded on the sale and its stock movements.
  final String? cashierId;
}

abstract class SaleRepository {
  /// Completed sales, newest first, for the history view.
  Stream<List<Sale>> watchRecentSales();

  Future<SaleDetail> loadSaleDetail(String saleId);

  /// Commits the whole sale atomically: sale + items + payments + SALE stock
  /// movements (§35). Prices are re-read from products, never trusted from the
  /// UI. Throws [StockShortageException] / [PaymentException] on failure.
  Future<CompletedSale> completeSale(SaleRequest request);
}

class DriftSaleRepository implements SaleRepository {
  DriftSaleRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  @override
  Stream<List<Sale>> watchRecentSales() {
    final query = _db.select(_db.sales)
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)])
      ..limit(200);
    return query.watch();
  }

  @override
  Future<SaleDetail> loadSaleDetail(String saleId) async {
    final sale = await (_db.select(
      _db.sales,
    )..where((s) => s.id.equals(saleId))).getSingle();

    final itemQuery = _db.select(_db.saleItems).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.saleItems.productId),
      ),
    ])..where(_db.saleItems.saleId.equals(saleId));
    final itemRows = await itemQuery.get();
    final items = [
      for (final row in itemRows)
        (
          item: row.readTable(_db.saleItems),
          productName: row.readTable(_db.products).name,
        ),
    ];

    final paymentsQuery = _db.select(_db.payments)
      ..where((p) => p.saleId.equals(saleId))
      ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]);
    final payments = await paymentsQuery.get();

    return SaleDetail(sale: sale, items: items, payments: payments);
  }

  @override
  Future<CompletedSale> completeSale(SaleRequest request) async {
    if (request.lines.isEmpty) {
      throw PaymentException('The cart is empty.');
    }

    final completed = await _db.transaction(() async {
      final productIds = request.lines.map((l) => l.productId).toSet();
      final products = await (_db.select(
        _db.products,
      )..where((p) => p.id.isIn(productIds))).get();
      final byId = {for (final p in products) p.id: p};
      for (final id in productIds) {
        if (!byId.containsKey(id)) {
          throw PaymentException('A cart product no longer exists.');
        }
      }

      // Authoritative prices + available stock from the ledger.
      final balances = await _balancesOf(productIds);
      final lines = <({String id, Product product, double quantity})>[];
      for (final line in request.lines) {
        final product = byId[line.productId]!;
        final available = balances[product.id] ?? 0;
        if (line.quantity <= 0) {
          throw StockShortageException(
            'Quantity must be positive for ${product.name}.',
          );
        }
        if (line.quantity > available) {
          throw StockShortageException(
            'Not enough stock for ${product.name}: '
            '$available available, ${_qty(line.quantity)} requested.',
          );
        }
        lines.add((id: product.id, product: product, quantity: line.quantity));
      }

      final totals = computeSaleTotals(
        lines: [
          for (final line in lines)
            (
              gross: line.product.sellingPrice * line.quantity,
              taxRate: line.product.taxRate,
            ),
        ],
        discount: request.discount,
      );

      final paid = request.payments.fold<double>(0, (sum, p) => sum + p.amount);
      if (paid < totals.total - 0.005) {
        throw PaymentException(
          'Payments (${formatMoney(paid)}) do not cover the total '
          '(${formatMoney(totals.total)}).',
        );
      }
      final change = paid - totals.total;

      final saleId = _uuid.v4();
      final now = DateTime.now();
      final receiptNumber = await _nextReceiptNumber();
      await _db
          .into(_db.sales)
          .insert(
            SalesCompanion(
              id: Value(saleId),
              receiptNumber: Value(receiptNumber),
              customerId: const Value<String?>(null),
              cashierId: Value<String?>(request.cashierId),
              subtotal: Value(totals.grossSubtotal),
              discount: Value(totals.discount),
              tax: Value(totals.taxIncluded),
              total: Value(totals.total),
              paymentStatus: const Value('PAID'),
              saleStatus: const Value('COMPLETED'),
              isSynced: Value(!WorkstationConfig.current.isClient),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      for (final line in lines) {
        final product = line.product;
        final gross = product.sellingPrice * line.quantity;
        final lineTax = product.taxRate > 0
            ? gross * (product.taxRate / (100 + product.taxRate))
            : 0.0;
        await _db
            .into(_db.saleItems)
            .insert(
              SaleItemsCompanion(
                id: Value(_uuid.v4()),
                saleId: Value(saleId),
                productId: Value(line.id),
                quantity: Value(line.quantity),
                unitPrice: Value(product.sellingPrice),
                discount: const Value(0),
                tax: Value(lineTax),
                subtotal: Value(gross),
                serialNumberId: const Value<String?>(null),
              ),
            );
      }

      for (final payment in request.payments) {
        await _db
            .into(_db.payments)
            .insert(
              PaymentsCompanion(
                id: Value(_uuid.v4()),
                saleId: Value(saleId),
                paymentMethod: Value(payment.method),
                amount: Value(payment.amount),
                reference: Value<String?>(payment.reference),
                createdAt: Value(now),
              ),
            );
      }

      // Stock ledger: one SALE movement per line (§13).
      for (final line in lines) {
        await _db
            .into(_db.stockMovements)
            .insert(
              StockMovementsCompanion(
                id: Value(_uuid.v4()),
                productId: Value(line.id),
                movementType: Value(MovementType.sale),
                quantity: Value(-line.quantity),
                referenceType: const Value<String?>('sale'),
                referenceId: Value<String?>(saleId),
                userId: Value<String?>(request.cashierId),
                reason: const Value<String?>(null),
                createdAt: Value(now),
              ),
            );
      }

      await AuditRepository(_db).log(
        action: AuditAction.sale,
        userId: request.cashierId,
        entityType: 'sale',
        entityId: saleId,
        details: '$receiptNumber — ${formatMoney(totals.total)}',
      );

      return CompletedSale(
        receiptNumber: receiptNumber,
        total: totals.total,
        change: change,
      );
    });

    if (WorkstationConfig.current.isClient) {
      LanSyncService.triggerSync();
    }

    return completed;
  }

  Future<Map<String, double>> _balancesOf(Set<String> productIds) async {
    final query = _db.selectOnly(_db.stockMovements)
      ..addColumns([
        _db.stockMovements.productId,
        _db.stockMovements.quantity.sum(),
      ])
      ..where(_db.stockMovements.productId.isIn(productIds))
      ..groupBy([_db.stockMovements.productId]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(_db.stockMovements.productId)!:
            row.read(_db.stockMovements.quantity.sum()) ?? 0,
    };
  }

  Future<String> _nextReceiptNumber() async {
    final statement = _db.selectOnly(_db.sales)
      ..addColumns([_db.sales.id.count()]);
    final count = await statement.getSingle();
    final next = (count.read(_db.sales.id.count()) ?? 0) + 1;
    return 'SA-${next.toString().padLeft(5, '0')}';
  }

  static String _qty(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}
