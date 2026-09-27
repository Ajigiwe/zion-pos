import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/features/imports/domain/import_document.dart';
import 'package:excel/excel.dart' as xl;

List<int> _csvBytes(String text) => utf8.encode(text);

void main() {
  group('parseImportFile · CSV', () {
    test('parses a standard file with header, numbers, barcode and aliases', () {
      const csv =
          'SKU,Barcode,Product Name,Category,Brand,Cost Price,Selling Price,'
          'Tax Rate (%),Reorder Level,Tracking,Quantity\n'
          'GTR-001,789123456001,Acoustic Guitar Starter,Guitars,Yamaha,180,320,0,2,quantity,5\n'
          'KEB-042,,61-Key Keyboard,Keyboards,Casio,95,160,,1,serialized,\n';
      final parsed = parseImportFile(
        fileName: 'stock.csv',
        bytes: _csvBytes(csv),
      )!;
      expect(parsed.problems, isEmpty);
      expect(parsed.rows, hasLength(2));

      final first = parsed.rows[0];
      expect(first.rowNumber, 2);
      expect(first.sku, 'GTR-001');
      expect(first.barcode, '789123456001');
      expect(first.name, 'Acoustic Guitar Starter');
      expect(first.category, 'Guitars');
      expect(first.brand, 'Yamaha');
      expect(first.costPrice, 180);
      expect(first.sellingPrice, 320);
      expect(first.taxRate, 0);
      expect(first.reorderLevel, 2);
      expect(first.quantity, 5);

      final second = parsed.rows[1];
      expect(second.barcode, isEmpty);
      expect(second.trackingType?.name, 'serialized');
      expect(second.quantity, isNull); // blank cell
    });

    test('accepts header aliases and tolerates locale number formats', () {
      // Quoted "1,250" is a thousand-separated integer; 12,5 is a decimal
      // comma (no dot present, not a thousands group of three).
      const body =
          'Item Code,Name,Category,Qty,Price,Tax\n'
          'X-1,Piano,Keyboards,"1,250",5000,0\n'
          'X-2,Drum Set,Percussion,"12,5",1250.5,15\n';
      final parsed = parseImportFile(
        fileName: 'a.csv',
        bytes: _csvBytes(body),
      )!;
      expect(parsed.rows, hasLength(2));
      expect(parsed.rows[0].quantity, 1250);
      expect(parsed.rows[1].quantity, 12.5);
      expect(parsed.rows[1].sellingPrice, 1250.5);
      expect(parsed.rows[1].taxRate, 15);
    });

    test('reports missing required columns and skips blank trailing rows', () {
      const csv =
          'SKU,Category,Quantity\n'
          'A-1,Guitars,3\n'
          ',,\n';
      final parsed = parseImportFile(
        fileName: 'bad.csv',
        bytes: _csvBytes(csv),
      )!;
      // Row A-1 still parses (validation flags missing fields later); the
      // fully blank row is dropped.
      expect(parsed.rows, hasLength(1));
      expect(parsed.rows.single.sku, 'A-1');
      expect(parsed.problems.join(' '), contains('Item Name'));
      expect(parsed.problems.join(' '), contains('Price (GHC)'));
    });

    test(
      'parses the store stock sheet format (ITEM NAME / PRICE (GHC) / QTY)',
      () {
        // Exactly the columns of the client's stock sheet, including the
        // currency suffix in the price header.
        const csv =
            'ITEM NAME,PRICE (GHC),QTY\n'
            '10\u201D Evans Double Velum,120,4\n'
            '12V Battery Rechargeable,85,6\n';
        final parsed = parseImportFile(
          fileName: 'stock-sheet.csv',
          bytes: _csvBytes(csv),
        )!;
        expect(parsed.problems, isEmpty);
        expect(parsed.rows, hasLength(2));
        expect(parsed.rows[0].name, '10\u201D Evans Double Velum');
        expect(parsed.rows[0].sellingPrice, 120);
        expect(parsed.rows[0].quantity, 4);
        expect(parsed.rows[1].name, '12V Battery Rechargeable');
        expect(parsed.rows[1].sellingPrice, 85);
        expect(parsed.rows[1].quantity, 6);
      },
    );

    test('rejects unsupported extensions', () {
      expect(
        parseImportFile(fileName: 'data.txt', bytes: _csvBytes('a,b')),
        isNull,
      );
    });
  });

  group('parseImportFile · xlsx', () {
    List<int> buildWorkbook(List<List<Object>> grid) {
      final book = xl.Excel.createExcel();
      final sheet = book['Sheet1'];
      for (final row in grid) {
        sheet.appendRow([
          for (final cell in row)
            switch (cell) {
              int() => xl.IntCellValue(cell),
              double() => xl.DoubleCellValue(cell),
              _ => xl.TextCellValue(cell.toString()),
            },
        ]);
      }
      return book.encode()!;
    }

    test('parses numbers and text from the first sheet', () {
      final bytes = buildWorkbook([
        ['SKU', 'Product Name', 'Selling Price', 'Quantity'],
        ['GTR-001', 'Acoustic Guitar Starter', 320, 5],
        ['KEB-042', '61-Key Keyboard', 160.5, 2],
      ]);
      final parsed = parseImportFile(fileName: 'stock.xlsx', bytes: bytes)!;
      expect(parsed.problems, isEmpty);
      expect(parsed.rows, hasLength(2));
      expect(parsed.rows[0].quantity, 5);
      expect(parsed.rows[0].sellingPrice, 320);
      expect(parsed.rows[1].sellingPrice, 160.5);
    });

    test('parses the client sheet format with a leading # column', () {
      // The store's own layout: # | ITEM NAME | PRICE (GHC) | QTY, with
      // numbers stored as real Excel numbers.
      final bytes = buildWorkbook([
        ['', 'ITEM NAME', 'PRICE (GHC)', 'QTY'],
        [1, '10\u201D Evans Double Velum', 120, 4],
        [2, '12V Battery Rechargeable', 85.5, 6],
      ]);
      final parsed = parseImportFile(
        fileName: 'stock-sheet.xlsx',
        bytes: bytes,
      )!;
      expect(parsed.problems, isEmpty);
      expect(parsed.rows, hasLength(2));
      expect(parsed.rows[0].name, '10\u201D Evans Double Velum');
      expect(parsed.rows[0].sellingPrice, 120);
      expect(parsed.rows[0].quantity, 4);
      expect(parsed.rows[0].rowNumber, 2);
      expect(parsed.rows[1].name, '12V Battery Rechargeable');
      expect(parsed.rows[1].sellingPrice, 85.5);
      expect(parsed.rows[1].quantity, 6);
      expect(parsed.rows[1].rowNumber, 3);
    });

    test('finds the header row below a title row with real row numbers', () {
      final bytes = buildWorkbook([
        ['Zion Musical Centre - Stock List'],
        [''],
        ['', 'ITEM NAME', 'PRICE (GHC)', 'QTY'],
        [1, '12\u201D GLS Speaker', 200, 2],
      ]);
      final parsed = parseImportFile(fileName: 'stock.xlsx', bytes: bytes)!;
      expect(parsed.problems, isEmpty);
      expect(parsed.rows, hasLength(1));
      expect(parsed.rows.single.name, '12\u201D GLS Speaker');
      // The title row is not treated as data, and the row number matches
      // the real spreadsheet row (header is row 3, data is row 4).
      expect(parsed.rows.single.rowNumber, 4);
    });

    test('prefers the sheet with stock headers over an earlier junk sheet', () {
      final book = xl.Excel.createExcel();
      final notes = book['Notes'];
      notes.appendRow([
        xl.TextCellValue('memo'),
        xl.TextCellValue('random notes, no headers here'),
      ]);
      final stock = book['Stock'];
      stock.appendRow([
        xl.TextCellValue('ITEM NAME'),
        xl.TextCellValue('PRICE (GHC)'),
        xl.TextCellValue('QTY'),
      ]);
      stock.appendRow([
        xl.TextCellValue('12V Battery Rechargeable'),
        xl.IntCellValue(85),
        xl.IntCellValue(6),
      ]);
      final parsed = parseImportFile(
        fileName: 'stock.xlsx',
        bytes: book.encode()!,
      )!;
      expect(parsed.problems, isEmpty);
      expect(parsed.rows, hasLength(1));
      expect(parsed.rows.single.name, '12V Battery Rechargeable');
      expect(parsed.rows.single.sellingPrice, 85);
      expect(parsed.rows.single.quantity, 6);
    });
  });

  test('template CSV pre-fills the store stock sheet with blank price/qty', () {
    final template = buildImportTemplateCsv();
    final parsed = parseImportFile(
      fileName: 'product-import-template.csv',
      bytes: utf8.encode(template),
    )!;
    expect(parsed.problems, isEmpty);
    // Header + every starter item from the client's sheet.
    expect(parsed.rows, hasLength(kStarterItems.length));
    expect(parsed.rows[0].name, kStarterItems.first);
    expect(parsed.rows[0].sku, isEmpty);
    expect(parsed.rows[0].sellingPrice, isNull);
    expect(parsed.rows[0].quantity, isNull);
    // Spot-check a middle row and the last row.
    expect(parsed.rows[5].name, '11\u201D Olympic Double');
    expect(parsed.rows.last.name, '12V Battery Rechargeable');
    // The template round-trips: importing it yields exactly the sheet names.
    expect(parsed.rows.map((r) => r.name), kStarterItems);
  });
}
