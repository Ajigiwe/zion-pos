import 'package:drift/drift.dart';

/// Users of the POS, mirroring the design doc's `users` entity.
/// `role` is one of OWNER, ADMIN, MANAGER, CASHIER, INVENTORY_MANAGER.
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get username => text().unique()();
  TextColumn get displayName => text()();
  TextColumn get passwordHash => text()();
  TextColumn get role => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Brands extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Whether a product is counted by quantity only, or tracked by serial number.
enum ProductTrackingType { quantity, serialized }

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get sku => text().unique()();
  TextColumn get barcode => text().nullable()();
  TextColumn get name => text()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get brandId => text().nullable().references(Brands, #id)();
  TextColumn get description => text().nullable()();

  /// Amounts stored in major currency units (e.g. GHS 4500).
  /// The minor-unit / decimal convention is an open decision to be locked
  /// before sales & payments are built.
  RealColumn get costPrice => real()();
  RealColumn get sellingPrice => real()();
  RealColumn get taxRate => real().withDefault(const Constant(0))();
  RealColumn get reorderLevel => real().withDefault(const Constant(0))();

  TextColumn get trackingType =>
      textEnum<ProductTrackingType>().withDefault(const Constant('quantity'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// How a customer paid, per design doc §12. A sale may have several payment
/// records (mixed payments); each record uses exactly one of these methods.
/// How a customer paid, per design doc §12. [exchangeCredit] is a synthetic
/// method recording the share of an exchange replacement paid with returned
/// goods' value.
enum PaymentMethod { cash, mobileMoney, card, bankTransfer, exchangeCredit }

/// A completed point-of-sale transaction (§11).
class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get receiptNumber => text().unique()();
  TextColumn get customerId => text().nullable()();
  TextColumn get cashierId => text().nullable()();

  /// Money in major units. subtotal is the gross of item prices before
  /// discount; prices are treated as tax-inclusive, so [tax] is informational
  /// and total = subtotal − discount.
  RealColumn get subtotal => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get tax => real().withDefault(const Constant(0))();
  RealColumn get total => real()();

  /// 'PAID' or later 'VOID'/'REFUNDED' — design doc §11.
  TextColumn get paymentStatus => text().withDefault(const Constant('PAID'))();
  TextColumn get saleStatus =>
      text().withDefault(const Constant('COMPLETED'))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// A single product line on a sale (§11). unitPrice snapshots the price at
/// sale time so later price changes never rewrite history.
class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get tax => real().withDefault(const Constant(0))();
  RealColumn get subtotal => real()();

  /// Populated for serialized products once serial tracking is implemented.
  TextColumn get serialNumberId => text().nullable()();
}

/// One payment record for a sale (§12). A cash + mobile money split is two
/// rows with the same saleId.
class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get paymentMethod => textEnum<PaymentMethod>()();
  RealColumn get amount => real()();
  TextColumn get reference => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Money returned to a customer against an original sale (§14). The original
/// sale is never modified or deleted.
class Refunds extends Table {
  TextColumn get id => text()();
  TextColumn get refundNumber => text().unique()();
  TextColumn get originalSaleId => text().references(Sales, #id)();
  TextColumn get cashierId => text().nullable()();
  TextColumn get refundMethod => textEnum<PaymentMethod>()();
  RealColumn get amount => real()();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Which original sale lines were returned and how much of each (§14).
class RefundItems extends Table {
  TextColumn get id => text()();
  TextColumn get refundId => text().references(Refunds, #id)();
  TextColumn get saleItemId => text().references(SaleItems, #id)();
  TextColumn get productId => text().references(Products, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get subtotal => real()();
}

/// An exchange links the return of goods from an original sale to a
/// replacement sale (§15). Stock moves as EXCHANGE_RETURN / EXCHANGE_SALE;
/// the replacement sale's payments include an exchangeCredit row.
class Exchanges extends Table {
  TextColumn get id => text()();
  TextColumn get exchangeNumber => text().unique()();
  TextColumn get originalSaleId => text().references(Sales, #id)();
  TextColumn get refundId => text().references(Refunds, #id)();
  TextColumn get replacementSaleId => text().references(Sales, #id)();
  RealColumn get returnTotal => real()();
  RealColumn get replacementTotal => real()();

  /// replacementTotal − returnTotal; positive means the customer paid the
  /// difference, negative means cash was returned.
  RealColumn get difference => real()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Generic local key/value settings. The store profile (printed on receipts)
/// lives under the keys 'store.name', 'store.address' and 'store.phone';
/// future settings (receipt footer, tax label…) can be added without a
/// schema change.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}

/// Immutable trail of who did what (§32). Actions like LOGIN, SALE, REFUND,
/// EXCHANGE, STOCK_ADJUSTMENT, USER_CREATE, BACKUP…
class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get action => text()();
  TextColumn get entityType => text().nullable()();
  TextColumn get entityId => text().nullable()();

  /// Human-readable summary of what changed (e.g. a receipt + total).
  TextColumn get details => text().nullable()();
  TextColumn get deviceId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// All stock movements recorded in the ledger, per design doc §13.
/// Current stock is SUM(quantity) over the ledger — never edited directly.
enum MovementType {
  openingStock,
  purchase,
  bulkImport,
  sale,
  refund,
  exchangeReturn,
  exchangeSale,
  damage,
  adjustment,
  transferIn,
  transferOut,
}

/// One committed bulk import (§20). importType is one of PRODUCT_IMPORT,
/// OPENING_STOCK or BULK_STOCK (design doc §20); [mode] records which of the
/// §21 bulk modes produced it so history stays unambiguous — e.g. a
/// BULK_STOCK batch may add stock (BULK_IMPORT movements) or set physical
/// counts (ADJUSTMENT movements). status: PENDING/COMPLETED/FAILED.
@DataClassName('ImportBatch')
class ImportBatches extends Table {
  TextColumn get id => text()();
  TextColumn get batchNumber => text().unique()();
  TextColumn get importType => text()();
  TextColumn get mode => text()();
  TextColumn get fileName => text()();
  IntColumn get totalRows => integer()();
  IntColumn get successfulRows => integer()();
  IntColumn get failedRows => integer()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('COMPLETED'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class StockMovements extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get movementType => textEnum<MovementType>()();
  RealColumn get quantity => real()();

  /// The business record that caused this movement, e.g. ('sale', SALE-1001).
  TextColumn get referenceType => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get userId => text().nullable()();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
