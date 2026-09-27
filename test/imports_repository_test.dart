import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/imports/data/import_repository.dart';
import 'package:instrument_pos/features/imports/domain/import_document.dart';

Future<Product> _addProduct(
  AppDatabase db,
  String name, {
  double price = 100,
  String? sku,
}) async {
  final id = 'prod-${name.toLowerCase().replaceAll(' ', '-')}';
  await db
      .into(db.products)
      .insert(
        ProductsCompanion(
          id: Value(id),
          sku: Value(sku ?? 'SKU-$name'),
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

Future<Map<String, double>> _balances(AppDatabase db) async {
  final query = db.selectOnly(db.stockMovements)
    ..addColumns([
      db.stockMovements.productId,
      db.stockMovements.quantity.sum(),
    ])
    ..groupBy([db.stockMovements.productId]);
  final rows = await query.get();
  return {
    for (final row in rows)
      row.read(db.stockMovements.productId)!:
          row.read(db.stockMovements.quantity.sum()) ?? 0,
  };
}

ParsedImport _parse(String text) => parseImportFile(
  fileName: 'jan.csv',
  bytes: utf8.encode(text),
)!; // Categories not part of the app's seeded defaults, so analysis counts them
// as "to create".
const _validRows =
    'SKU,Product Name,Category,Brand,Selling Price,Quantity\n'
    'GTR-001,Acoustic Guitar,Woodwinds,Yamaha,320,5\n'
    'KEB-001,Keyboard,Synthesizers,Casio,160,10\n';

void main() {
  late AppDatabase db;
  late DriftBulkImportRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftBulkImportRepository(db);
  });

  tearDown(() => db.close());

  test(
    'addStock creates products, categories and BULK_IMPORT movements',
    () async {
      final parsed = _parse(_validRows);
      final analysis = await repo.analyze(
        document: parsed,
        mode: ImportMode.addStock,
      );
      expect(analysis.problems, isEmpty);
      expect(analysis.validRows, 2);
      expect(analysis.newProducts, 2);
      expect(analysis.categoriesToCreate, 2);
      expect(analysis.brandsToCreate, 2);
      expect(analysis.unitsIn, 15);

      final result = await repo.commit(
        document: parsed,
        analysis: analysis,
        userId: 'u-owner',
      );
      expect(result.batch.batchNumber, 'IMP-00001');
      expect(result.batch.totalRows, 2);
      expect(result.batch.successfulRows, 2);
      expect(result.batch.failedRows, 0);
      expect(result.batch.importType, 'BULK_STOCK');
      expect(result.batch.mode, 'addStock');
      expect(result.productsCreated, 2);
      expect(result.movementsRecorded, 2);
      expect(result.unitsIn, 15);

      // Ledger holds the truth: +5 and +10 as BULK_IMPORT movements.
      final keyboard = (await (db.select(
        db.products,
      )..where((p) => p.sku.equals('KEB-001'))).getSingle());
      expect(await _balance(db, keyboard.id), 10);
      final movements = await (db.select(
        db.stockMovements,
      )..where((m) => m.productId.equals(keyboard.id))).get();
      expect(movements.single.movementType, MovementType.bulkImport);
      expect(movements.single.quantity, 10);
      expect(movements.single.userId, 'u-owner');
      expect(movements.single.referenceType, 'import');

      // Categories/brands were created; the batch is in history.
      expect(
        (await db.select(db.categories).get()).map((c) => c.name),
        contains('Guitars'),
      );
      expect(
        (await db.select(db.brands).get()).map((b) => b.name),
        contains('Yamaha'),
      );
      expect((await repo.watchBatches().first).single.batchNumber, 'IMP-00001');
      expect(
        (await db.select(db.auditLogs).get()).map((l) => l.action),
        contains('IMPORT'),
      );
    },
  );

  test(
    'addStock updates an existing product instead of duplicating it',
    () async {
      await _addProduct(db, 'Acoustic Guitar', price: 300, sku: 'GTR-001');
      final parsed = _parse(_validRows);
      final analysis = await repo.analyze(
        document: parsed,
        mode: ImportMode.addStock,
      );
      expect(analysis.newProducts, 1);
      expect(analysis.existingProducts, 1);

      final result = await repo.commit(document: parsed, analysis: analysis);
      expect(result.productsCreated, 1);
      expect(result.productsUpdated, 1);

      // Same SKU re-imported later updates rather than creating a third row.
      final again = await repo.analyze(
        document: parsed,
        mode: ImportMode.addStock,
      );
      final second = await repo.commit(document: parsed, analysis: again);
      expect(second.productsCreated, 0);
      expect(second.productsUpdated, 2);
      expect((await db.select(db.products).get()), hasLength(2));

      final guitar = (await (db.select(
        db.products,
      )..where((p) => p.sku.equals('GTR-001'))).getSingle());
      expect(guitar.sellingPrice, 320); // updated price
      expect(await _balance(db, guitar.id), 10); // 5 + 5 from both imports
    },
  );

  test('openingStock mode refuses products that already have stock', () async {
    await _addProduct(db, 'Keyboard', sku: 'KEB-001');
    final inventory = InventoryRepositoryForTest(db);
    await inventory.opening('prod-keyboard', 4);

    final parsed = _parse(_validRows);
    final analysis = await repo.analyze(
      document: parsed,
      mode: ImportMode.openingStock,
    );
    // Guitar row is fine; keyboard already has stock -> row error.
    expect(analysis.validRows, 1);
    expect(
      analysis.issues.map((i) => i.display).join('\n'),
      contains('already has stock'),
    );

    final result = await repo.commit(document: parsed, analysis: analysis);
    expect(result.movementsRecorded, 1); // only the guitar movement
    expect(result.batch.importType, 'OPENING_STOCK');
    final guitar = (await (db.select(
      db.products,
    )..where((p) => p.sku.equals('GTR-001'))).getSingle());
    expect(await _balance(db, guitar.id), 5);
    final guitarMovements = await (db.select(
      db.stockMovements,
    )..where((m) => m.productId.equals(guitar.id))).get();
    expect(guitarMovements.single.movementType, MovementType.openingStock);
  });

  test(
    'setPhysical books ADJUSTMENT deltas and skips no-change rows',
    () async {
      await _addProduct(db, 'Acoustic Guitar', sku: 'GTR-001');
      await _addProduct(db, 'Keyboard', sku: 'KEB-001');
      final inventory = InventoryRepositoryForTest(db);
      await inventory.opening('prod-acoustic-guitar', 3);
      await inventory.opening('prod-keyboard', 10);

      const csv =
          'SKU,Product Name,Selling Price,Quantity\n'
          'GTR-001,Acoustic Guitar,320,8\n' // 3 -> 8: +5 ADJUSTMENT
          'KEB-001,Keyboard,160,10\n' // unchanged: no movement
          'AMP-001,Amplifier,999,2\n'; // new product starts at 2
      final parsed = _parse(csv);
      final analysis = await repo.analyze(
        document: parsed,
        mode: ImportMode.setPhysical,
      );
      expect(analysis.validRows, 3);
      expect(analysis.noChangeRows, 1);
      expect(analysis.unitsIn, 7);
      expect(analysis.unitsOut, 0);
      final result = await repo.commit(document: parsed, analysis: analysis);
      expect(result.movementsRecorded, 2);
      final balances = await _balances(db);
      expect(balances['prod-acoustic-guitar'], 8);
      expect(balances['prod-keyboard'], 10);
      // The amplifier is a brand-new product created by the import (its id is a
      // generated UUID, so resolve it through the SKU).
      final amplifier = (await (db.select(
        db.products,
      )..where((p) => p.sku.equals('AMP-001'))).getSingle());
      expect(await _balance(db, amplifier.id), 2);

      final adjustment =
          await (db.select(db.stockMovements)..where(
                (m) =>
                    m.productId.equals('prod-acoustic-guitar') &
                    m.movementType.equalsValue(MovementType.adjustment),
              ))
              .get();
      expect(adjustment.single.quantity, 5);
      expect(adjustment.single.reason, 'Physical stock count (import)');
    },
  );

  test(
    'setPhysical can reduce stock below current and writes negative delta',
    () async {
      await _addProduct(db, 'Keyboard', sku: 'KEB-001');
      final inventory = InventoryRepositoryForTest(db);
      await inventory.opening('prod-keyboard', 10);

      const csv =
          'SKU,Product Name,Selling Price,Quantity\n'
          'KEB-001,Keyboard,160,6\n';
      final parsed = _parse(csv);
      final analysis = await repo.analyze(
        document: parsed,
        mode: ImportMode.setPhysical,
      );
      expect(analysis.unitsOut, 4);

      final result = await repo.commit(document: parsed, analysis: analysis);
      expect(result.movementsRecorded, 1);
      expect(await _balance(db, 'prod-keyboard'), 6);
      final movement =
          (await (db.select(db.stockMovements)..where(
                    (m) =>
                        m.productId.equals('prod-keyboard') &
                        m.movementType.equalsValue(MovementType.adjustment),
                  ))
                  .get())
              .single;
      expect(movement.quantity, -4);
      expect(movement.reason, 'Physical stock count (import)');
    },
  );

  test('productOnly never writes stock movements', () async {
    final parsed = _parse(_validRows);
    final analysis = await repo.analyze(
      document: parsed,
      mode: ImportMode.productOnly,
    );
    expect(analysis.unitsIn, 0);
    final result = await repo.commit(document: parsed, analysis: analysis);
    expect(result.movementsRecorded, 0);
    expect(result.batch.importType, 'PRODUCT_IMPORT');
    expect(await db.select(db.stockMovements).get(), isEmpty);
  });

  test(
    'row validation reports bad prices, quantities and duplicate SKUs',
    () async {
      const csv =
          'SKU,Product Name,Selling Price,Quantity\n'
          'A-1,Good Thing,50,2\n'
          'A-1,Duplicate SKU,50,2\n'
          'B-2,No Price,,5\n'
          'C-3,Negative Qty,20,-1\n';
      final parsed = _parse(csv);
      final analysis = await repo.analyze(
        document: parsed,
        mode: ImportMode.addStock,
      );
      expect(analysis.validRows, 1);
      final messages = analysis.issues.map((i) => i.message).join('\n');
      expect(messages, contains('duplicated in the file'));
      expect(messages, contains('Selling price is missing'));
      expect(messages, contains('Quantity cannot be negative'));
      expect(analysis.issueCount, 3);
    },
  );

  test(
    'missing quantity column blocks stock modes with a batch problem',
    () async {
      const csv = 'SKU,Product Name,Selling Price\nA-1,Keyboard,160\n';
      final parsed = _parse(csv);
      final analysis = await repo.analyze(
        document: parsed,
        mode: ImportMode.addStock,
      );
      expect(analysis.problems, isNotEmpty);
      expect(analysis.canImport, isFalse);
    },
  );

  test('commit refuses a file that failed batch-level analysis', () async {
    const csv = 'SKU,Product Name\nA-1,Keyboard\n';
    final parsed = _parse(csv);
    final analysis = await repo.analyze(
      document: parsed,
      mode: ImportMode.productOnly,
    );
    expect(analysis.canImport, isFalse);
    expect(
      () => repo.commit(document: parsed, analysis: analysis),
      throwsA(isA<StateError>()),
    );
  });

  test('imports product barcode and matches existing products by barcode', () async {
    const csv =
        'SKU,Barcode,Product Name,Selling Price,Quantity\n'
        'SKU-101,123456789012,Digital Piano,500,3\n';
    final parsed = _parse(csv);
    final analysis = await repo.analyze(
      document: parsed,
      mode: ImportMode.productOnly,
    );
    expect(analysis.validRows, 1);
    await repo.commit(document: parsed, analysis: analysis);

    final product = await (db.select(db.products)
          ..where((p) => p.sku.equals('SKU-101')))
        .getSingle();
    expect(product.barcode, '123456789012');

    // Re-import file matching by barcode with updated price
    const updateCsv =
        'SKU,Barcode,Product Name,Selling Price,Quantity\n'
        'NEW-SKU,123456789012,Digital Piano Pro,550,5\n';
    final updateParsed = _parse(updateCsv);
    final updateAnalysis = await repo.analyze(
      document: updateParsed,
      mode: ImportMode.productOnly,
    );
    expect(updateAnalysis.existingProducts, 1);
    await repo.commit(document: updateParsed, analysis: updateAnalysis);

    final updatedProduct = await (db.select(db.products)
          ..where((p) => p.barcode.equals('123456789012')))
        .getSingle();
    expect(updatedProduct.id, product.id);
    expect(updatedProduct.sellingPrice, 550);
  });
}

/// Thin helper to open stock without importing InventoryRepository types in
/// test signatures (avoids ambiguity with the feature's own repository).
class InventoryRepositoryForTest {
  InventoryRepositoryForTest(this.db);

  final AppDatabase db;

  Future<void> opening(String productId, int quantity) {
    return db
        .into(db.stockMovements)
        .insert(
          StockMovementsCompanion(
            id: Value('m-$productId-$quantity'),
            productId: Value(productId),
            movementType: Value(MovementType.openingStock),
            quantity: Value(quantity.toDouble()),
            reason: const Value('Opening stock'),
            createdAt: Value(DateTime(2026, 2, 1)),
          ),
        );
  }
}
