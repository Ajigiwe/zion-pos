import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/inventory/domain/stock_sheet_document.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';

Product makeProduct(String id, String name, {double price = 320}) => Product(
  id: id,
  sku: 'SKU-$id',
  barcode: null,
  name: name,
  categoryId: null,
  brandId: null,
  description: null,
  costPrice: 100,
  sellingPrice: price,
  taxRate: 0,
  reorderLevel: 0,
  trackingType: ProductTrackingType.quantity,
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  rev: 1, dirty: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = kStoreInfo;
  final now = DateTime(2026, 9, 4);

  test('produces a valid PDF with the stock-sheet layout', () async {
    final bytes = await buildStockSheetPdf(
      store: store,
      products: [
        ProductWithStock(
          product: makeProduct('p1', '12\u201D GLS Speaker'),
          stock: 4,
        ),
        ProductWithStock(
          product: makeProduct('p2', '12V Battery', price: 85),
          stock: 6.5,
        ),
      ],
      now: now,
    );
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(1500));
  });

  test('document grows with the number of products', () async {
    final few = await buildStockSheetPdf(
      store: store,
      products: [
        for (var i = 0; i < 3; i++)
          ProductWithStock(product: makeProduct('p$i', 'Item $i'), stock: 1),
      ],
      now: now,
    );
    final many = await buildStockSheetPdf(
      store: store,
      products: [
        for (var i = 0; i < 60; i++)
          ProductWithStock(product: makeProduct('p$i', 'Item $i'), stock: 1),
      ],
      now: now,
    );
    expect(many.length, greaterThan(few.length));
  });

  test('empty catalog still renders a printable sheet', () async {
    final bytes = await buildStockSheetPdf(
      store: store,
      products: const [],
      now: now,
    );
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(800));
  });
}
