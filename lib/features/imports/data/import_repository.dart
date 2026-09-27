import 'package:drift/drift.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';
import 'package:instrument_pos/features/imports/domain/import_document.dart';
import 'package:uuid/uuid.dart';

/// One problem on one imported row, e.g. "Row 42 · YAM-001 · Selling price is missing".
class RowIssue {
  const RowIssue({
    required this.rowNumber,
    required this.identity,
    required this.message,
  });

  final int rowNumber;
  final String identity;
  final String message;

  String get display => 'Row $rowNumber · $identity · $message';
}

/// Result of validating a parsed file against the catalog and ledger.
class ImportAnalysis {
  const ImportAnalysis({
    required this.mode,
    required this.totalRows,
    required this.validRows,
    required this.issueCount,
    required this.issues,
    required this.problems,
    required this.newProducts,
    required this.existingProducts,
    required this.categoriesToCreate,
    required this.brandsToCreate,
    required this.unitsIn,
    required this.unitsOut,
    required this.noChangeRows,
  });

  final ImportMode mode;

  /// Data rows found in the file (blank trailing rows are dropped at parse).
  final int totalRows;
  final int validRows;

  /// Rows with at least one error (validRows + issueCount ≙ totalRows only
  /// when every row has at most one issue; row-level errors are unique).
  final int issueCount;
  final List<RowIssue> issues;

  /// Batch-level problems that block the whole import (missing columns…).
  final List<String> problems;

  /// Valid rows whose SKU/name does not exist in the catalog yet.
  final int newProducts;

  /// Valid rows matching an existing product (updated in place).
  final int existingProducts;

  final int categoriesToCreate;
  final int brandsToCreate;

  /// Units the import will add to stock (mode-dependent deltas).
  final double unitsIn;

  /// Units the import will remove from stock (physical counts below current).
  final double unitsOut;

  /// setPhysical rows where the file quantity already equals system stock.
  final int noChangeRows;

  bool get canImport => problems.isEmpty && validRows > 0;
}

/// Result of a committed import batch.
class CommitResult {
  const CommitResult({
    required this.batch,
    required this.productsCreated,
    required this.productsUpdated,
    required this.movementsRecorded,
    required this.unitsIn,
    required this.unitsOut,
  });

  final ImportBatch batch;
  final int productsCreated;
  final int productsUpdated;
  final int movementsRecorded;
  final double unitsIn;
  final double unitsOut;
}

abstract class BulkImportRepository {
  /// Validates parsed rows against the catalog and ledger for [mode] —
  /// SKU uniqueness, prices, quantities, opening-stock conflicts, and the
  /// category/brand names that would need creating. Read-only.
  Future<ImportAnalysis> analyze({
    required ParsedImport document,
    required ImportMode mode,
  });

  /// Commits an analyzed import atomically: products, ledger movements
  /// (BULK_IMPORT / OPENING_STOCK / ADJUSTMENT), the batch record and the
  /// audit entry all in one transaction (§38, §39). Row-level issues from the
  /// analysis are skipped; catalog/lookup conflicts are re-checked in the
  /// transaction. Returns the recorded counts.
  Future<CommitResult> commit({
    required ParsedImport document,
    required ImportAnalysis analysis,
    String? userId,
  });

  /// Live list of import batches, newest first.
  Stream<List<ImportBatch>> watchBatches({int limit = 100});
}

class DriftBulkImportRepository implements BulkImportRepository {
  DriftBulkImportRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  // ---------------------------------------------------------------- analysis

  @override
  Future<ImportAnalysis> analyze({
    required ParsedImport document,
    required ImportMode mode,
  }) async {
    final problems = List<String>.of(document.problems);
    if (mode.touchesStock &&
        !document.rows.any((row) => row.quantity != null)) {
      problems.add(
        'This mode needs the "Quantity" column, but no row has a quantity. '
        'Use "Products only", or add quantities to the file.',
      );
    }

    final products = await _db.select(_db.products).get();
    final bySku = {
      for (final product in products) product.sku.toLowerCase(): product,
    };
    final byBarcode = {
      for (final product in products)
        if (product.barcode != null && product.barcode!.trim().isNotEmpty)
          product.barcode!.trim().toLowerCase(): product,
    };
    final byName = {
      for (final product in products) product.name.toLowerCase(): product,
    };
    final categoryNames = {
      for (final category in await _db.select(_db.categories).get())
        category.name.toLowerCase(): category.name,
    };
    final brandNames = {
      for (final brand in await _db.select(_db.brands).get())
        brand.name.toLowerCase(): brand.name,
    };
    final balances = await _stockBalances();

    final issues = <RowIssue>[];
    final seenSkus = <String, int>{};
    final seenBarcodes = <String, int>{};
    var newProducts = 0;
    var existingProducts = 0;
    var categoriesToCreate = 0;
    var brandsToCreate = 0;
    var noChangeRows = 0;
    var unitsIn = 0.0;
    var unitsOut = 0.0;

    for (final row in document.rows) {
      final rowIssues = <String>[];

      if (row.name.isEmpty) {
        rowIssues.add('Product name is required.');
      }
      final sku = row.sku.trim().toLowerCase();
      if (sku.isNotEmpty) {
        final earlier = seenSkus[sku];
        if (earlier != null) {
          rowIssues.add(
            'SKU ${row.sku} is duplicated in the file (row $earlier).',
          );
        } else {
          seenSkus[sku] = row.rowNumber;
        }
      }

      final barcode = row.barcode.trim().toLowerCase();
      if (barcode.isNotEmpty) {
        final earlier = seenBarcodes[barcode];
        if (earlier != null) {
          rowIssues.add(
            'Barcode ${row.barcode} is duplicated in the file (row $earlier).',
          );
        } else {
          seenBarcodes[barcode] = row.rowNumber;
        }
      }

      final selling = row.sellingPrice;
      if (selling == null) {
        rowIssues.add('Selling price is missing.');
      } else if (selling <= 0) {
        rowIssues.add('Selling price must be greater than zero.');
      }
      final cost = row.costPrice;
      if (cost != null && cost < 0) {
        rowIssues.add('Cost price cannot be negative.');
      }
      final tax = row.taxRate;
      if (tax != null && (tax < 0 || tax > 100)) {
        rowIssues.add('Tax rate must be between 0 and 100.');
      }
      final reorder = row.reorderLevel;
      if (reorder != null && reorder < 0) {
        rowIssues.add('Reorder level cannot be negative.');
      }
      if (row.trackingType == null) {
        rowIssues.add('Tracking must be "quantity" or "serialized".');
      }
      if (row.quantity == null && mode.touchesStock) {
        rowIssues.add('Quantity is required in ${mode.label} mode.');
      } else if (row.quantity != null) {
        final quantity = row.quantity!;
        if (quantity < 0) {
          rowIssues.add('Quantity cannot be negative.');
        } else if (quantity == 0 && mode != ImportMode.setPhysical) {
          rowIssues.add('Quantity must be greater than zero.');
        }
      }

      // Catalog hit: by SKU, barcode, else by exact name (case-insensitive).
      final existing =
          (sku.isNotEmpty ? bySku[sku] : null) ??
          (barcode.isNotEmpty ? byBarcode[barcode] : null) ??
          byName[row.name.trim().toLowerCase()];
      if (rowIssues.isEmpty) {
        if (row.category.isNotEmpty &&
            !categoryNames.containsKey(row.category.toLowerCase())) {
          categoriesToCreate++;
        }
        if (row.brand.isNotEmpty &&
            !brandNames.containsKey(row.brand.toLowerCase())) {
          brandsToCreate++;
        }
        if (existing == null) {
          newProducts++;
        } else {
          existingProducts++;
        }

        if (mode.touchesStock) {
          final current = existing == null ? 0.0 : (balances[existing.id] ?? 0);
          final target = row.quantity ?? 0;
          switch (mode) {
            case ImportMode.addStock:
              unitsIn += target;
            case ImportMode.openingStock:
              if (current != 0) {
                rowIssues.add(
                  '${existing!.name} already has stock '
                  '(${_trim(current)} units) — use "Add stock" or '
                  '"Set to physical count" instead.',
                );
                existingProducts--; // still catalog-matched but the row fails
              } else {
                unitsIn += target;
              }
            case ImportMode.setPhysical:
              final delta = target - current;
              if (delta > 0) unitsIn += delta;
              if (delta < 0) unitsOut += -delta;
              if (delta == 0) noChangeRows++;
            case ImportMode.productOnly:
              break;
          }
        }
      }

      for (final message in rowIssues) {
        issues.add(
          RowIssue(
            rowNumber: row.rowNumber,
            identity: row.identity,
            message: message,
          ),
        );
      }
    }

    final issueRows = <int>{for (final issue in issues) issue.rowNumber}.length;
    return ImportAnalysis(
      mode: mode,
      totalRows: document.rows.length,
      validRows: document.rows.length - issueRows,
      issueCount: issues.length,
      issues: issues,
      problems: problems,
      newProducts: newProducts,
      existingProducts: existingProducts,
      categoriesToCreate: categoriesToCreate,
      brandsToCreate: brandsToCreate,
      unitsIn: unitsIn,
      unitsOut: unitsOut,
      noChangeRows: noChangeRows,
    );
  }

  // ------------------------------------------------------------------ commit

  @override
  Future<CommitResult> commit({
    required ParsedImport document,
    required ImportAnalysis analysis,
    String? userId,
  }) async {
    if (analysis.problems.isNotEmpty || analysis.validRows == 0) {
      throw StateError('Refusing to import a file that failed analysis.');
    }
    final mode = analysis.mode;
    final issuesByRow = <int, String>{
      for (final issue in analysis.issues) issue.rowNumber: issue.message,
    };

    final CommitResult result = await _db.transaction(() async {
      // Snapshot the catalog and ledger inside the transaction so the commit
      // always agrees with the latest state (§39).
      final products = await _db.select(_db.products).get();
      final bySku = {for (final p in products) p.sku.toLowerCase(): p};
      final byBarcode = {
        for (final p in products)
          if (p.barcode != null && p.barcode!.trim().isNotEmpty)
            p.barcode!.trim().toLowerCase(): p,
      };
      final byName = {for (final p in products) p.name.toLowerCase(): p};
      final categoryByName = {
        for (final c in await _db.select(_db.categories).get())
          c.name.toLowerCase(): c,
      };
      final brandByName = {
        for (final b in await _db.select(_db.brands).get())
          b.name.toLowerCase(): b,
      };
      final balances = await _stockBalances();

      var created = 0;
      var updated = 0;
      var movements = 0;
      var unitsIn = 0.0;
      var unitsOut = 0.0;
      final now = DateTime.now();

      for (final row in document.rows) {
        if (issuesByRow.containsKey(row.rowNumber)) continue;
        final skuLower = row.sku.trim().toLowerCase();
        final barcodeLower = row.barcode.trim().toLowerCase();
        final nameLower = row.name.trim().toLowerCase();
        var product =
            (skuLower.isNotEmpty ? bySku[skuLower] : null) ??
            (barcodeLower.isNotEmpty ? byBarcode[barcodeLower] : null) ??
            byName[nameLower];

        // Category/brand are created on the fly when the file names a new one.
        String? categoryId;
        if (row.category.isNotEmpty) {
          final existing = categoryByName[row.category.toLowerCase()];
          if (existing != null) {
            categoryId = existing.id;
          } else {
            final id = _uuid.v4();
            await _db
                .into(_db.categories)
                .insert(
                  CategoriesCompanion(
                    id: Value(id),
                    name: Value(row.category.trim()),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                  ),
                );
            categoryByName[row.category.toLowerCase()] = Category(
              id: id,
              name: row.category.trim(),
              description: null,
              createdAt: now,
              updatedAt: now,
            );
            categoryId = id;
          }
        }
        String? brandId;
        if (row.brand.isNotEmpty) {
          final existing = brandByName[row.brand.toLowerCase()];
          if (existing != null) {
            brandId = existing.id;
          } else {
            final id = _uuid.v4();
            await _db
                .into(_db.brands)
                .insert(
                  BrandsCompanion(
                    id: Value(id),
                    name: Value(row.brand.trim()),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                  ),
                );
            brandByName[row.brand.toLowerCase()] = Brand(
              id: id,
              name: row.brand.trim(),
              description: null,
              createdAt: now,
              updatedAt: now,
            );
            brandId = id;
          }
        }

        final productId = product?.id ?? _uuid.v4();
        final resolvedSku = row.sku.trim().isNotEmpty
            ? row.sku.trim()
            : _deriveSku(row.name);
        final resolvedBarcode = row.barcode.trim().isNotEmpty
            ? row.barcode.trim()
            : product?.barcode;
        final companion = ProductsCompanion(
          id: Value(productId),
          sku: Value(resolvedSku),
          barcode: Value(resolvedBarcode),
          name: Value(row.name.trim()),
          categoryId: Value<String?>(categoryId),
          brandId: Value<String?>(brandId),
          costPrice: Value(row.costPrice ?? (product?.costPrice ?? 0)),
          sellingPrice: Value(row.sellingPrice ?? 0),
          taxRate: Value(row.taxRate ?? (product?.taxRate ?? 0)),
          reorderLevel: Value(row.reorderLevel ?? (product?.reorderLevel ?? 0)),
          trackingType: Value(row.trackingType ?? ProductTrackingType.quantity),
          createdAt: Value(product?.createdAt ?? now),
          updatedAt: Value(now),
        );
        if (product == null) {
          // Brand-new product: insert and register it for later rows.
          created++;
          await _db.into(_db.products).insert(companion);
          final rowSnapshot = Product(
            id: productId,
            sku: resolvedSku,
            barcode: resolvedBarcode,
            name: row.name.trim(),
            categoryId: categoryId,
            brandId: brandId,
            description: null,
            costPrice: row.costPrice ?? 0,
            sellingPrice: row.sellingPrice ?? 0,
            taxRate: row.taxRate ?? 0,
            reorderLevel: row.reorderLevel ?? 0,
            trackingType: row.trackingType ?? ProductTrackingType.quantity,
            isActive: true,
            createdAt: now,
            updatedAt: now,
          );
          bySku[resolvedSku.toLowerCase()] = rowSnapshot;
          if (resolvedBarcode != null && resolvedBarcode.isNotEmpty) {
            byBarcode[resolvedBarcode.toLowerCase()] = rowSnapshot;
          }
          byName[nameLower] = rowSnapshot;
        } else {
          // Existing product (matched by SKU, barcode, or name): update in place.
          updated++;
          await (_db.update(
            _db.products,
          )..where((p) => p.id.equals(productId))).write(companion);
          final rowSnapshot = Product(
            id: productId,
            sku: resolvedSku,
            barcode: resolvedBarcode,
            name: row.name.trim(),
            categoryId: categoryId ?? product.categoryId,
            brandId: brandId ?? product.brandId,
            description: product.description,
            costPrice: row.costPrice ?? product.costPrice,
            sellingPrice: row.sellingPrice ?? product.sellingPrice,
            taxRate: row.taxRate ?? product.taxRate,
            reorderLevel: row.reorderLevel ?? product.reorderLevel,
            trackingType: row.trackingType ?? product.trackingType,
            isActive: product.isActive,
            createdAt: product.createdAt,
            updatedAt: now,
          );
          bySku[resolvedSku.toLowerCase()] = rowSnapshot;
          if (resolvedBarcode != null && resolvedBarcode.isNotEmpty) {
            byBarcode[resolvedBarcode.toLowerCase()] = rowSnapshot;
          }
          byName[nameLower] = rowSnapshot;
        }

        if (mode.touchesStock) {
          // Keep the in-transaction balance current so repeated rows for the
          // same product (physical mode) each adjust from the latest state.
          final current = balances[productId] ?? 0;
          final target = row.quantity ?? 0;
          final double delta;
          final MovementType movementType;
          final String reason;
          switch (mode) {
            case ImportMode.addStock:
              delta = target;
              movementType = MovementType.bulkImport;
              reason = 'Bulk import';
            case ImportMode.openingStock:
              delta = target;
              movementType = MovementType.openingStock;
              reason = 'Opening stock';
            case ImportMode.setPhysical:
              delta = target - current;
              movementType = MovementType.adjustment;
              reason = 'Physical stock count (import)';
            case ImportMode.productOnly:
              delta = 0;
              movementType = MovementType.purchase;
              reason = '';
          }
          balances[productId] = current + delta;
          if (delta != 0) {
            await _db
                .into(_db.stockMovements)
                .insert(
                  StockMovementsCompanion(
                    id: Value(_uuid.v4()),
                    productId: Value(productId),
                    movementType: Value(movementType),
                    quantity: Value(delta),
                    referenceType: const Value('import'),
                    reason: Value<String?>(reason),
                    userId: Value<String?>(userId),
                    createdAt: Value(now),
                  ),
                );
            movements++;
            if (delta > 0) unitsIn += delta;
            if (delta < 0) unitsOut += -delta;
          }
        }
      }

      final batch = await _insertBatch(
        document: document,
        analysis: analysis,
        created: created,
        updated: updated,
        userId: userId,
      );

      return CommitResult(
        batch: batch,
        productsCreated: created,
        productsUpdated: updated,
        movementsRecorded: movements,
        unitsIn: unitsIn,
        unitsOut: unitsOut,
      );
    });

    await AuditRepository(_db).log(
      action: AuditAction.importBatch,
      userId: userId,
      entityType: 'import',
      entityId: result.batch.id,
      details:
          '${result.batch.batchNumber} · ${mode.label} · '
          '${result.batch.fileName} · '
          '${result.batch.successfulRows}/${result.batch.totalRows} rows ok, '
          '${result.batch.failedRows} failed · '
          '${result.productsCreated} created, ${result.productsUpdated} updated · '
          '${result.movementsRecorded} stock movements',
    );
    return result;
  }

  Future<ImportBatch> _insertBatch({
    required ParsedImport document,
    required ImportAnalysis analysis,
    required int created,
    required int updated,
    String? userId,
  }) async {
    final query = _db.selectOnly(_db.importBatches)
      ..addColumns([_db.importBatches.id.count()]);
    final count =
        (await query.getSingle()).read(_db.importBatches.id.count()) ?? 0;
    final batch = ImportBatch(
      id: _uuid.v4(),
      batchNumber: 'IMP-${(count + 1).toString().padLeft(5, '0')}',
      importType: analysis.mode.importType,
      mode: analysis.mode.storageName,
      fileName: document.fileName,
      totalRows: analysis.totalRows,
      successfulRows: analysis.validRows,
      failedRows: analysis.issueCount == 0
          ? 0
          : analysis.totalRows - analysis.validRows,
      createdBy: userId,
      status: 'COMPLETED',
      createdAt: DateTime.now(),
    );
    await _db
        .into(_db.importBatches)
        .insert(
          ImportBatchesCompanion(
            id: Value(batch.id),
            batchNumber: Value(batch.batchNumber),
            importType: Value(batch.importType),
            mode: Value(batch.mode),
            fileName: Value(batch.fileName),
            totalRows: Value(batch.totalRows),
            successfulRows: Value(batch.successfulRows),
            failedRows: Value(batch.failedRows),
            createdBy: Value<String?>(batch.createdBy),
            status: Value(batch.status),
            createdAt: Value(batch.createdAt),
          ),
        );
    return batch;
  }

  @override
  Stream<List<ImportBatch>> watchBatches({int limit = 100}) {
    final query = _db.select(_db.importBatches)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);
    return query.watch();
  }

  // ----------------------------------------------------------------- helpers

  /// Sum of all ledger movements per product — the authoritative stock value.
  Future<Map<String, double>> _stockBalances() async {
    final query = _db.selectOnly(_db.stockMovements)
      ..addColumns([
        _db.stockMovements.productId,
        _db.stockMovements.quantity.sum(),
      ])
      ..groupBy([_db.stockMovements.productId]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(_db.stockMovements.productId)!:
            row.read(_db.stockMovements.quantity.sum()) ?? 0,
    };
  }

  static String _deriveSku(String name) {
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return '${slug.substring(0, slug.length.clamp(1, 16))}-${_uuid.v4().substring(0, 6)}'
        .toUpperCase();
  }

  static String _trim(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

/// Formatting helper shared by analysis preview text.
String formatUnits(double units) => units == units.roundToDouble()
    ? units.toStringAsFixed(0)
    : units.toString();
