import 'package:drift/drift.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/core/numbering/document_numbers.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';
import 'package:instrument_pos/features/refunds/domain/refund_models.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/domain/receipt_customization.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';
import 'package:uuid/uuid.dart';

abstract class RefundsRepository {
  Stream<List<RefundWithReceipt>> watchRefunds();

  Stream<List<ExchangeWithReceipt>> watchExchanges();

  /// How much of each original sale line may still be returned.
  Future<Map<String, double>> remainingQuantitiesFor(String saleId);

  /// Refunds a customer for returned goods. The original sale stays intact;
  /// stock returns via REFUND movements (§14, §36).
  Future<CompletedRefund> createRefund(RefundRequest request);

  /// Runs a whole exchange atomically: return stock (EXCHANGE_RETURN),
  /// a replacement sale (EXCHANGE_SALE movements) whose payments include an
  /// exchange-credit row, and an exchange link record (§15, §37).
  Future<CompletedExchange> createExchange(ExchangeRequest request);

  /// Builds a complete ReceiptContent for a past refund.
  Future<ReceiptContent> getRefundReceipt(
    String refundId, {
    required StoreInfo store,
    required ReceiptCustomization customization,
  });

  /// Builds a complete ReceiptContent for a past exchange.
  Future<ReceiptContent> getExchangeReceipt(
    String exchangeId, {
    required StoreInfo store,
    required ReceiptCustomization customization,
  });
}

class RefundWithReceipt {
  const RefundWithReceipt({
    required this.refund,
    required this.saleReceiptNumber,
  });

  final Refund refund;
  final String saleReceiptNumber;
}

class ExchangeWithReceipt {
  const ExchangeWithReceipt({
    required this.exchange,
    required this.saleReceiptNumber,
    required this.replacementReceiptNumber,
  });

  final Exchange exchange;
  final String saleReceiptNumber;
  final String replacementReceiptNumber;
}

class DriftRefundsRepository implements RefundsRepository {
  DriftRefundsRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  // ------------------------------------------------------------- read paths

  @override
  Stream<List<RefundWithReceipt>> watchRefunds() {
    final query = _db.select(_db.refunds).join([
      innerJoin(_db.sales, _db.sales.id.equalsExp(_db.refunds.originalSaleId)),
    ])..orderBy([OrderingTerm.desc(_db.refunds.createdAt)]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          RefundWithReceipt(
            refund: row.readTable(_db.refunds),
            saleReceiptNumber: row.readTable(_db.sales).receiptNumber,
          ),
      ],
    );
  }

  @override
  Future<Map<String, double>> remainingQuantitiesFor(String saleId) async {
    final items = await _saleItemsOf(saleId);

    return _remainingQuantities(items.map((item) => item.id).toSet());
  }

  @override
  Stream<List<ExchangeWithReceipt>> watchExchanges() {
    final original = _db.alias(_db.sales, 'original_sale');
    final replacement = _db.alias(_db.sales, 'replacement_sale');
    final query = _db.select(_db.exchanges).join([
      innerJoin(original, original.id.equalsExp(_db.exchanges.originalSaleId)),
      innerJoin(
        replacement,
        replacement.id.equalsExp(_db.exchanges.replacementSaleId),
      ),
    ])..orderBy([OrderingTerm.desc(_db.exchanges.createdAt)]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          ExchangeWithReceipt(
            exchange: row.readTable(_db.exchanges),
            saleReceiptNumber: row.readTable(original).receiptNumber,
            replacementReceiptNumber: row.readTable(replacement).receiptNumber,
          ),
      ],
    );
  }

  // ----------------------------------------------------------------- refund

  @override
  Future<CompletedRefund> createRefund(RefundRequest request) async {
    if (request.lines.isEmpty) {
      throw RefundException('Select at least one item to refund.');
    }
    if (request.method == PaymentMethod.exchangeCredit) {
      throw RefundException('Standalone refunds cannot use exchange credit.');
    }
    return _db.transaction(() async {
      final saleItems = await _saleItemsOf(request.originalSaleId);
      final remaining = await _remainingQuantities(
        saleItems.map((item) => item.id).toSet(),
      );

      var amount = 0.0;
      var itemCount = 0;
      final validated = <(SaleItem, double)>[];
      for (final line in request.lines) {
        final item = saleItems
            .where((s) => s.id == line.saleItemId)
            .firstOrNull;
        if (item == null) {
          throw RefundException(
            'A selected line is not part of the original sale.',
          );
        }
        final left = remaining[item.id] ?? item.quantity;
        if (line.quantity <= 0 || line.quantity > left) {
          throw RefundException(
            'Cannot refund more than the remaining quantity (${_qty(left)}) '
            'for this line.',
          );
        }
        validated.add((item, line.quantity));
        amount += item.unitPrice * line.quantity;
        itemCount += 1;
      }

      final now = DateTime.now();
      final refundId = _uuid.v4();
      final refundNumber = await _nextRefundNumber();
      await _db
          .into(_db.refunds)
          .insert(
            RefundsCompanion(
              id: Value(refundId),
              refundNumber: Value(refundNumber),
              originalSaleId: Value(request.originalSaleId),
              cashierId: Value<String?>(request.cashierId),
              refundMethod: Value(request.method),
              amount: Value(amount),
              reason: Value<String?>(request.reason),
              createdAt: Value(now),
            ),
          );

      for (final entry in validated) {
        await _insertRefundItem(refundId, entry.$1, entry.$2);
        await _db
            .into(_db.stockMovements)
            .insert(
              StockMovementsCompanion(
                id: Value(_uuid.v4()),
                productId: Value(entry.$1.productId),
                movementType: Value(MovementType.refund),
                quantity: Value(entry.$2),
                referenceType: const Value<String?>('refund'),
                referenceId: Value<String?>(refundId),
                userId: Value<String?>(request.cashierId),
                reason: Value<String?>(request.reason ?? 'Refund'),
                createdAt: Value(now),
              ),
            );
      }
      await AuditRepository(_db).log(
        action: AuditAction.refund,
        userId: request.cashierId,
        entityType: 'refund',
        entityId: refundId,
        details: '$refundNumber against sale — ${_money(amount)}',
      );

      return CompletedRefund(
        refundId: refundId,
        refundNumber: refundNumber,
        amount: amount,
        itemCount: itemCount,
      );
    });
  }

  // --------------------------------------------------------------- exchange

  @override
  Future<CompletedExchange> createExchange(ExchangeRequest request) async {
    if (request.returnedLines.isEmpty) {
      throw RefundException('Select the items being exchanged.');
    }
    if (request.replacements.isEmpty) {
      throw RefundException('Choose a replacement product.');
    }
    return _db.transaction(() async {
      // Validate returns against the original sale.
      final saleItems = await _saleItemsOf(request.originalSaleId);
      final remaining = await _remainingQuantities(
        saleItems.map((item) => item.id).toSet(),
      );
      var returnCredit = 0.0;
      for (final line in request.returnedLines) {
        final item = saleItems
            .where((s) => s.id == line.saleItemId)
            .firstOrNull;
        if (item == null) {
          throw RefundException(
            'A returned line is not part of the original sale.',
          );
        }
        final left = remaining[item.id] ?? item.quantity;
        if (line.quantity <= 0 || line.quantity > left) {
          throw RefundException(
            'Cannot exchange more than the remaining quantity (${_qty(left)}) '
            'for this line.',
          );
        }
        returnCredit += item.unitPrice * line.quantity;
      }

      // Replacement prices + stock from the ledger (authoritative).
      final ids = request.replacements.map((r) => r.productId).toSet();
      final products = await (_db.select(
        _db.products,
      )..where((p) => p.id.isIn(ids))).get();
      final byId = {for (final p in products) p.id: p};
      final balances = await _balancesOf(ids);
      var replacementTotal = 0.0;
      final validatedReplacement =
          <({String productId, Product product, double quantity})>[];
      for (final line in request.replacements) {
        final product = byId[line.productId];
        if (product == null) {
          throw RefundException('A replacement product no longer exists.');
        }
        final available = balances[product.id] ?? 0;
        if (line.quantity <= 0 || line.quantity > available) {
          throw RefundException(
            'Not enough stock for ${product.name}: ${_qty(available)} available.',
          );
        }
        validatedReplacement.add((
          productId: product.id,
          product: product,
          quantity: line.quantity,
        ));
        replacementTotal += product.sellingPrice * line.quantity;
      }

      final breakdown = computeExchangeBreakdown(
        returnCredit: returnCredit,
        replacementTotal: replacementTotal,
      );
      final paid = request.balancePayments.fold<double>(
        0,
        (sum, p) => sum + p.amount,
      );
      if (breakdown.balanceDue > 0 && paid < breakdown.balanceDue - 0.005) {
        throw RefundException(
          'The customer must pay ${_money(breakdown.balanceDue)} — '
          'only ${_money(paid)} captured.',
        );
      }
      if (breakdown.balanceDue == 0 && paid > 0.005) {
        throw RefundException(
          'No balance payment is needed — the returned goods cover the replacement.',
        );
      }

      final now = DateTime.now();
      final cashierId = request.cashierId;

      // 1. Return record + EXCHANGE_RETURN stock movements.
      final refundId = _uuid.v4();
      final refundNumber = await _nextRefundNumber();
      await _db
          .into(_db.refunds)
          .insert(
            RefundsCompanion(
              id: Value(refundId),
              refundNumber: Value(refundNumber),
              originalSaleId: Value(request.originalSaleId),
              cashierId: Value<String?>(cashierId),
              refundMethod: Value(PaymentMethod.exchangeCredit),
              amount: Value(breakdown.returnCredit),
              reason: const Value<String?>('Exchange return'),
              createdAt: Value(now),
            ),
          );
      for (final line in request.returnedLines) {
        final item = saleItems.where((s) => s.id == line.saleItemId).first;
        await _insertRefundItem(refundId, item, line.quantity);
        await _db
            .into(_db.stockMovements)
            .insert(
              StockMovementsCompanion(
                id: Value(_uuid.v4()),
                productId: Value(item.productId),
                movementType: Value(MovementType.exchangeReturn),
                quantity: Value(line.quantity),
                referenceType: const Value<String?>('refund'),
                referenceId: Value<String?>(refundId),
                userId: Value<String?>(cashierId),
                reason: const Value<String?>('Exchange return'),
                createdAt: Value(now),
              ),
            );
      }

      // 2. Cash back when the replacement is cheaper (no extra stock move).
      var exchangeRefundId = refundId;
      if (breakdown.cashBack > 0) {
        exchangeRefundId = _uuid.v4();
        final cashBackNumber = await _nextRefundNumber();
        await _db
            .into(_db.refunds)
            .insert(
              RefundsCompanion(
                id: Value(exchangeRefundId),
                refundNumber: Value(cashBackNumber),
                originalSaleId: Value(request.originalSaleId),
                cashierId: Value<String?>(cashierId),
                refundMethod: Value(PaymentMethod.cash),
                amount: Value(breakdown.cashBack),
                reason: const Value<String?>('Exchange cash back'),
                createdAt: Value(now),
              ),
            );
      }

      // 3. Replacement sale (receipt + history) with EXCHANGE_SALE movements.
      final saleId = _uuid.v4();
      final receiptNumber = await _nextSaleNumber();
      final saleTotals = computeSaleTotals(
        lines: [
          for (final line in validatedReplacement)
            (
              gross: line.product.sellingPrice * line.quantity,
              taxRate: line.product.taxRate,
            ),
        ],
        discount: 0,
      );
      await _db
          .into(_db.sales)
          .insert(
            SalesCompanion(
              id: Value(saleId),
              receiptNumber: Value(receiptNumber),
              customerId: const Value<String?>(null),
              cashierId: Value<String?>(cashierId),
              subtotal: Value(saleTotals.grossSubtotal),
              discount: Value(saleTotals.discount),
              tax: Value(saleTotals.taxIncluded),
              total: Value(saleTotals.total),
              paymentStatus: const Value('PAID'),
              saleStatus: const Value('COMPLETED'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      for (final line in validatedReplacement) {
        final gross = line.product.sellingPrice * line.quantity;
        await _db
            .into(_db.saleItems)
            .insert(
              SaleItemsCompanion(
                id: Value(_uuid.v4()),
                saleId: Value(saleId),
                productId: Value(line.productId),
                quantity: Value(line.quantity),
                unitPrice: Value(line.product.sellingPrice),
                discount: const Value(0),
                tax: Value(
                  line.product.taxRate > 0
                      ? gross *
                            (line.product.taxRate /
                                (100 + line.product.taxRate))
                      : 0.0,
                ),
                subtotal: Value(gross),
                serialNumberId: const Value<String?>(null),
              ),
            );
        await _db
            .into(_db.stockMovements)
            .insert(
              StockMovementsCompanion(
                id: Value(_uuid.v4()),
                productId: Value(line.productId),
                movementType: Value(MovementType.exchangeSale),
                quantity: Value(-line.quantity),
                referenceType: const Value<String?>('sale'),
                referenceId: Value<String?>(saleId),
                userId: Value<String?>(cashierId),
                reason: const Value<String?>('Exchange replacement'),
                createdAt: Value(now),
              ),
            );
      }
      if (breakdown.exchangeCredit > 0) {
        await _insertPayment(
          saleId,
          PaymentMethod.exchangeCredit,
          breakdown.exchangeCredit,
          'EXCHANGE-$refundNumber',
          now,
        );
      }
      for (final payment in request.balancePayments) {
        await _insertPayment(
          saleId,
          payment.method,
          payment.amount,
          payment.reference,
          now,
        );
      }

      // 4. Link the exchange.
      final exchangeId = _uuid.v4();
      final exchangeNumber = await _nextExchangeNumber();
      await _db
          .into(_db.exchanges)
          .insert(
            ExchangesCompanion(
              id: Value(exchangeId),
              exchangeNumber: Value(exchangeNumber),
              originalSaleId: Value(request.originalSaleId),
              refundId: Value(exchangeRefundId),
              replacementSaleId: Value(saleId),
              returnTotal: Value(breakdown.returnCredit),
              replacementTotal: Value(breakdown.replacementTotal),
              difference: Value(
                breakdown.replacementTotal - breakdown.returnCredit,
              ),
              createdAt: Value(now),
            ),
          );

      await AuditRepository(_db).log(
        action: AuditAction.exchange,
        userId: cashierId,
        entityType: 'exchange',
        entityId: exchangeId,
        details:
            '$exchangeNumber — return ${_money(breakdown.returnCredit)}, '
            'replacement $receiptNumber (${_money(breakdown.replacementTotal)})',
      );

      return CompletedExchange(
        exchangeId: exchangeId,
        exchangeNumber: exchangeNumber,
        replacementReceiptNumber: receiptNumber,
        returnCredit: breakdown.returnCredit,
        replacementTotal: breakdown.replacementTotal,
        cashBack: breakdown.cashBack,
      );
    });
  }

  // --------------------------------------------------------------- helpers

  Future<void> _insertRefundItem(
    String refundId,
    SaleItem item,
    double quantity,
  ) async {
    await _db
        .into(_db.refundItems)
        .insert(
          RefundItemsCompanion(
            id: Value(_uuid.v4()),
            refundId: Value(refundId),
            saleItemId: Value(item.id),
            productId: Value(item.productId),
            quantity: Value(quantity),
            unitPrice: Value(item.unitPrice),
            subtotal: Value(item.unitPrice * quantity),
          ),
        );
  }

  Future<void> _insertPayment(
    String saleId,
    PaymentMethod method,
    double amount,
    String? reference,
    DateTime now,
  ) async {
    await _db
        .into(_db.payments)
        .insert(
          PaymentsCompanion(
            id: Value(_uuid.v4()),
            saleId: Value(saleId),
            paymentMethod: Value(method),
            amount: Value(amount),
            reference: Value<String?>(reference),
            createdAt: Value(now),
          ),
        );
  }

  Future<List<SaleItem>> _saleItemsOf(String saleId) async {
    final query = _db.select(_db.saleItems)
      ..where((item) => item.saleId.equals(saleId));
    return query.get();
  }

  /// Sold minus already returned (refunds and exchanges both record
  /// RefundItems rows), per original sale line.
  Future<Map<String, double>> _remainingQuantities(
    Set<String> saleItemIds,
  ) async {
    if (saleItemIds.isEmpty) return {};
    final query = _db.selectOnly(_db.refundItems)
      ..addColumns([_db.refundItems.saleItemId, _db.refundItems.quantity.sum()])
      ..where(_db.refundItems.saleItemId.isIn(saleItemIds))
      ..groupBy([_db.refundItems.saleItemId]);
    final rows = await query.get();
    final returned = {
      for (final row in rows)
        row.read(_db.refundItems.saleItemId)!:
            row.read(_db.refundItems.quantity.sum()) ?? 0.0,
    };
    final items = await (_db.select(
      _db.saleItems,
    )..where((item) => item.id.isIn(saleItemIds))).get();
    return {
      for (final item in items)
        item.id: item.quantity - (returned[item.id] ?? 0),
    };
  }

  Future<Map<String, double>> _balancesOf(Set<String> productIds) async {
    if (productIds.isEmpty) return {};
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

  Future<String> _nextSaleNumber() => nextDocumentNumber(
    _db,
    table: 'sales',
    column: 'receipt_number',
    prefix: 'SA',
  );

  Future<String> _nextRefundNumber() => nextDocumentNumber(
    _db,
    table: 'refunds',
    column: 'refund_number',
    prefix: 'RF',
  );

  Future<String> _nextExchangeNumber() => nextDocumentNumber(
    _db,
    table: 'exchanges',
    column: 'exchange_number',
    prefix: 'EX',
  );

  @override
  Future<ReceiptContent> getRefundReceipt(
    String refundId, {
    required StoreInfo store,
    required ReceiptCustomization customization,
  }) async {
    final refund = await (_db.select(_db.refunds)
          ..where((r) => r.id.equals(refundId)))
        .getSingle();

    final originalSale = await (_db.select(_db.sales)
          ..where((s) => s.id.equals(refund.originalSaleId)))
        .getSingle();

    final refundItemsQuery = _db.select(_db.refundItems).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.refundItems.productId),
      ),
    ])..where(_db.refundItems.refundId.equals(refundId));

    final rows = await refundItemsQuery.get();
    final returnedLines = <ReceiptLine>[
      for (final row in rows)
        (
          name: row.readTable(_db.products).name,
          quantity: row.readTable(_db.refundItems).quantity,
          unitPrice: row.readTable(_db.refundItems).unitPrice,
        ),
    ];

    String? cashierName;
    if (refund.cashierId != null) {
      final user = await (_db.select(_db.users)
            ..where((u) => u.id.equals(refund.cashierId!)))
          .getSingleOrNull();
      cashierName = user?.displayName;
    }

    return ReceiptContent(
      store: store,
      receiptNumber: refund.refundNumber,
      originalReceiptNumber: originalSale.receiptNumber,
      createdAt: refund.createdAt,
      title: 'REFUND RECEIPT',
      returnedLines: returnedLines,
      lines: const [],
      totals: SaleTotals(
        grossSubtotal: refund.amount,
        discount: 0,
        taxIncluded: 0,
        total: refund.amount,
      ),
      payments: [
        PaymentDraft(method: refund.refundMethod, amount: refund.amount),
      ],
      cashierName: cashierName,
      customization: customization,
    );
  }

  @override
  Future<ReceiptContent> getExchangeReceipt(
    String exchangeId, {
    required StoreInfo store,
    required ReceiptCustomization customization,
  }) async {
    final exchange = await (_db.select(_db.exchanges)
          ..where((e) => e.id.equals(exchangeId)))
        .getSingle();

    final originalSale = await (_db.select(_db.sales)
          ..where((s) => s.id.equals(exchange.originalSaleId)))
        .getSingle();

    final replacementSale = await (_db.select(_db.sales)
          ..where((s) => s.id.equals(exchange.replacementSaleId)))
        .getSingle();

    // Returned lines
    final refundItemsQuery = _db.select(_db.refundItems).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.refundItems.productId),
      ),
    ])..where(_db.refundItems.refundId.equals(exchange.refundId));

    final refundRows = await refundItemsQuery.get();
    final returnedLines = <ReceiptLine>[
      for (final row in refundRows)
        (
          name: row.readTable(_db.products).name,
          quantity: row.readTable(_db.refundItems).quantity,
          unitPrice: row.readTable(_db.refundItems).unitPrice,
        ),
    ];

    // Replacement lines
    final saleItemsQuery = _db.select(_db.saleItems).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.saleItems.productId),
      ),
    ])..where(_db.saleItems.saleId.equals(exchange.replacementSaleId));

    final saleRows = await saleItemsQuery.get();
    final replacementLines = <ReceiptLine>[
      for (final row in saleRows)
        (
          name: row.readTable(_db.products).name,
          quantity: row.readTable(_db.saleItems).quantity,
          unitPrice: row.readTable(_db.saleItems).unitPrice,
        ),
    ];

    // Replacement payments
    final pRows = await (_db.select(_db.payments)
          ..where((p) => p.saleId.equals(exchange.replacementSaleId)))
        .get();

    final payments = <PaymentDraft>[
      for (final p in pRows)
        if (p.paymentMethod != PaymentMethod.exchangeCredit)
          PaymentDraft(
            method: p.paymentMethod,
            amount: p.amount,
            reference: p.reference,
          ),
    ];

    String? cashierName;
    if (replacementSale.cashierId != null) {
      final user = await (_db.select(_db.users)
            ..where((u) => u.id.equals(replacementSale.cashierId!)))
          .getSingleOrNull();
      cashierName = user?.displayName;
    }

    final netDifference = exchange.difference.abs();

    return ReceiptContent(
      store: store,
      receiptNumber: exchange.exchangeNumber,
      originalReceiptNumber: originalSale.receiptNumber,
      createdAt: exchange.createdAt,
      title: 'EXCHANGE RECEIPT',
      returnedLines: returnedLines,
      lines: replacementLines,
      returnCredit: exchange.returnTotal,
      replacementTotal: exchange.replacementTotal,
      totals: SaleTotals(
        grossSubtotal: exchange.replacementTotal,
        discount: 0,
        taxIncluded: replacementSale.tax,
        total: netDifference,
      ),
      payments: payments,
      cashierName: cashierName,
      customization: customization,
    );
  }

  static String _qty(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  static String _money(double value) => 'GHS ${value.toStringAsFixed(2)}';
}
