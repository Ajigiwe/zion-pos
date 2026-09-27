import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:instrument_pos/core/database/tables.dart';

/// The four bulk import modes (§21). Each maps to specific ledger movements
/// and to one of the design's import batch types (§20).
enum ImportMode {
  /// Catalog only: products are created/updated, quantity is ignored.
  productOnly,

  /// "Add Stock": current + quantity, BULK_IMPORT movements, BULK_STOCK batch.
  addStock,

  /// "Opening Inventory": for products with no stock yet, OPENING_STOCK
  /// movements, OPENING_STOCK batch.
  openingStock,

  /// "Inventory Adjustment": quantity is the physical count, ADJUSTMENT
  /// movements for the difference, BULK_STOCK batch (mode stored separately).
  setPhysical;

  String get label => switch (this) {
    ImportMode.productOnly => 'Products only',
    ImportMode.addStock => 'Add stock',
    ImportMode.openingStock => 'Opening stock',
    ImportMode.setPhysical => 'Set to physical count',
  };

  String get description => switch (this) {
    ImportMode.productOnly =>
      'Creates or updates catalog entries only — quantity is ignored.',
    ImportMode.addStock =>
      'Adds the file quantity to current stock (BULK_IMPORT +qty).',
    ImportMode.openingStock => 'Sets initial stock (OPENING_STOCK +qty) — only for products with no stock yet.',
    ImportMode.setPhysical => 'Treats the quantity as the physical count and books an ADJUSTMENT for the difference.',
  };

  /// Whether this mode writes stock movements at all.
  bool get touchesStock => this != ImportMode.productOnly;

  /// The design doc §20 batch import type this mode commits as.
  String get importType => switch (this) {
    ImportMode.productOnly => 'PRODUCT_IMPORT',
    ImportMode.openingStock => 'OPENING_STOCK',
    ImportMode.addStock || ImportMode.setPhysical => 'BULK_STOCK',
  };

  String get storageName => name;

  static ImportMode fromStorage(String value) => ImportMode.values.firstWhere(
    (mode) => mode.storageName == value,
    orElse: () => ImportMode.addStock,
  );
}

/// One data row from an uploaded file, with numbers already parsed so
/// validation and preview logic stay free of string handling.
class ImportRowData {
  const ImportRowData({
    required this.rowNumber,
    this.sku = '',
    this.barcode = '',
    this.name = '',
    this.category = '',
    this.brand = '',
    this.costPrice,
    this.sellingPrice,
    this.taxRate,
    this.reorderLevel,
    this.trackingType,
    this.quantity,
  });

  /// 1-based row in the spreadsheet, header row included.
  final int rowNumber;

  final String sku;
  final String barcode;
  final String name;
  final String category;
  final String brand;

  final double? costPrice;
  final double? sellingPrice;
  final double? taxRate;
  final double? reorderLevel;
  final ProductTrackingType? trackingType;
  final double? quantity;

  /// Short label used in error messages and previews.
  String get identity =>
      sku.isNotEmpty ? sku : (name.isNotEmpty ? name : 'row $rowNumber');
}

/// A parsed file: rows plus batch-level problems (e.g. a missing column).
class ParsedImport {
  const ParsedImport({
    required this.fileName,
    required this.rows,
    required this.problems,
  });

  final String fileName;
  final List<ImportRowData> rows;
  final List<String> problems;
}

/// Parse .csv or .xlsx bytes into rows. Pure — no database access.
/// Returns null when the format is unsupported or the file has no data.
ParsedImport? parseImportFile({
  required String fileName,
  required List<int> bytes,
}) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.csv')) return _parseCsv(fileName, bytes);
  if (lower.endsWith('.xlsx')) return _parseXlsx(fileName, bytes);
  return null;
}

ParsedImport _parseCsv(String fileName, List<int> bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  if (text.trim().isEmpty) {
    return ParsedImport(
      fileName: fileName,
      rows: const [],
      problems: const ['The file is empty.'],
    );
  }
  final eol = text.contains('\r\n') ? '\r\n' : '\n';
  final rows = const CsvToListConverter(shouldParseNumbers: false)
      .convert(text, eol: eol);
  return _gridToImport(fileName, rows);
}

ParsedImport _parseXlsx(String fileName, List<int> bytes) {
  try {
    final book = xl.Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) {
      return ParsedImport(
        fileName: fileName,
        rows: const [],
        problems: const ['The workbook has no sheets.'],
      );
    }
    final sheet = _selectStockSheet(book);
    final rows = <List<String>>[];
    for (var r = 0; r < sheet.maxRows; r++) {
      rows.add([for (final cell in sheet.rows[r]) _excelCellText(cell)]);
    }
    return _gridToImport(fileName, rows);
  } catch (_) {
    return ParsedImport(
      fileName: fileName,
      rows: const [],
      problems: const ['Could not read this Excel file.'],
    );
  }
}

/// The first sheet whose header row carries item-name and price headers —
/// Excel workbooks often start with a junk or notes sheet. Falls back to
/// the workbook's first sheet when none looks like stock data.
xl.Sheet _selectStockSheet(xl.Excel book) {
  final sheets = book.tables.values.toList();
  for (final sheet in sheets) {
    for (var r = 0; r < sheet.maxRows; r++) {
      if (_rowHasStockHeaders([
        for (final cell in sheet.rows[r]) _excelCellText(cell),
      ])) {
        return sheet;
      }
    }
  }
  return sheets.first;
}

String _excelCellText(xl.Data? cell) {
  final value = cell?.value;
  if (value == null) return '';
  return switch (value) {
    xl.IntCellValue() => value.value.toString(),
    xl.DoubleCellValue() =>
      value.value == value.value.roundToDouble()
          ? value.value.toInt().toString()
          : value.value.toString(),
    xl.TextCellValue() => value.value.toString().trim(),
    _ => value.toString().trim(),
  };
}

/// Column headers accepted by the importer (compared case-insensitively).
const Map<String, Set<String>> _headerAliases = {
  'sku': {'sku', 'item code'},
  'barcode': {'barcode', 'bar code', 'upc', 'ean', 'code'},
  'name': {'product name', 'name', 'product', 'item name'},
  'category': {'category', 'category name'},
  'brand': {'brand', 'brand name'},
  'cost': {'cost', 'cost price', 'unit cost'},
  'selling': {
    'selling price',
    'selling',
    'price',
    'unit price',
    'price (ghc)',
    'price (ghs)',
    'selling price (ghc)',
    'selling price (ghs)',
  },
  'tax': {'tax rate (%)', 'tax rate', 'tax %', 'tax'},
  'reorder': {'reorder level', 'reorder point', 'min stock'},
  'tracking': {'tracking', 'tracking type'},
  'quantity': {'quantity', 'qty', 'stock', 'opening qty', 'quantity on hand'},
};

/// Whether a row looks like a stock-sheet header (an item-name column and
/// a price column per the accepted aliases).
bool _rowHasStockHeaders(List<String> row) {
  bool has(String key) =>
      row.any((cell) => _headerAliases[key]!.contains(cell.toLowerCase()));
  return has('name') && has('selling');
}

/// The index of the first row carrying stock headers, or -1. Real sheets
/// often have a title or logo row above the header row.
int _findHeaderRow(List<List<String>> grid) {
  for (var r = 0; r < grid.length; r++) {
    if (_rowHasStockHeaders(grid[r])) return r;
  }
  return -1;
}

ParsedImport _gridToImport(String fileName, List<List<dynamic>> rows) {
  final grid = [
    for (final row in rows)
      [for (final cell in row) (cell ?? '').toString().trim()],
  ];
  final hasAnyCell = grid.any((row) => row.any((cell) => cell.isNotEmpty));
  if (!hasAnyCell) {
    return ParsedImport(
      fileName: fileName,
      rows: const [],
      problems: const ['The file is empty.'],
    );
  }

  final problems = <String>[];
  final headerRowIndex = _findHeaderRow(grid);
  final headers = [
    for (final cell in grid[headerRowIndex < 0 ? 0 : headerRowIndex])
      cell.toLowerCase(),
  ];
  final firstDataRow = headerRowIndex < 0 ? 1 : headerRowIndex + 1;

  int columnOf(String key) {
    final aliases = _headerAliases[key]!;
    for (var i = 0; i < headers.length; i++) {
      if (aliases.contains(headers[i])) return i;
    }
    return -1;
  }

  final columns = {for (final key in _headerAliases.keys) key: columnOf(key)};
  if (columns['name'] == -1) {
    problems.add('The file is missing an "Item Name" column.');
  }
  if (columns['selling'] == -1) {
    problems.add('The file is missing a "Price (GHC)" column.');
  }

  final parsed = <ImportRowData>[];
  for (var r = firstDataRow; r < grid.length; r++) {
    final cells = grid[r];
    String cell(int? index) =>
        index != null && index >= 0 && index < cells.length ? cells[index] : '';

    final name = cell(columns['name']);
    if (name.isEmpty &&
        cell(columns['sku']).isEmpty &&
        cell(columns['barcode']).isEmpty &&
        cell(columns['selling']).isEmpty) {
      continue; // fully blank trailing row
    }

    final costText = cell(columns['cost']);
    final sellingText = cell(columns['selling']);
    final taxText = cell(columns['tax']);
    final reorderText = cell(columns['reorder']);
    final quantityText = cell(columns['quantity']);
    final trackingText = cell(columns['tracking']).toLowerCase();

    final trackingType = trackingText.isEmpty
        ? ProductTrackingType.quantity
        : switch (trackingText) {
            'quantity' || 'qty' => ProductTrackingType.quantity,
            'serialized' || 'serial' => ProductTrackingType.serialized,
            _ => null,
          };

    parsed.add(
      ImportRowData(
        rowNumber: r + 1,
        sku: cell(columns['sku']),
        barcode: cell(columns['barcode']),
        name: name,
        category: cell(columns['category']),
        brand: cell(columns['brand']),
        costPrice: costText.isEmpty ? null : _parseNumber(costText),
        sellingPrice: sellingText.isEmpty ? null : _parseNumber(sellingText),
        taxRate: taxText.isEmpty ? null : _parseNumber(taxText),
        reorderLevel: reorderText.isEmpty ? null : _parseNumber(reorderText),
        trackingType: trackingType,
        quantity: quantityText.isEmpty ? null : _parseNumber(quantityText),
      ),
    );
  }

  if (parsed.isEmpty && problems.isEmpty) {
    problems.add('No data rows were found below the header row.');
  }
  return ParsedImport(fileName: fileName, rows: parsed, problems: problems);
}

/// Parses a numeric cell, tolerating locale formatting: "1,250" (thousands)
/// and "12,5" (decimal comma) both resolve correctly; when a dot is present
/// commas are treated as thousands separators.
double? _parseNumber(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final hasComma = t.contains(',');
  final hasDot = t.contains('.');
  String candidate = t;
  if (hasComma && !hasDot) {
    final thousands = RegExp(r'^([0-9]+),([0-9]{3})$').firstMatch(t);
    if (thousands != null) {
      candidate = '${thousands.group(1)}${thousands.group(2)}';
    } else {
      candidate = t.replaceAll(',', '.');
    }
  } else if (hasComma) {
    candidate = t.replaceAll(',', '');
  }
  return double.tryParse(candidate);
}

/// Canonical template columns in order (used by [buildImportTemplate]).
/// Mirrors the store's stock sheet: item name, price, and quantity first,
/// with the optional enrichment columns after.
const List<String> kImportTemplateHeaders = [
  'Item Name',
  'Price (GHC)',
  'Qty',
  'SKU',
  'Barcode',
  'Category',
  'Brand',
  'Cost Price',
  'Tax Rate (%)',
  'Reorder Level',
  'Tracking',
];

/// The store's current stock sheet (item names only; prices and quantities
/// are filled in by staff before importing).
const List<String> kStarterItems = [
  '(01/100 (S)',
  '10\u201D Evans Double Velum',
  '10\u201D GLS Naked Speaker',
  '10\u201D Naked Speaker',
  '10\u201D Olympic Single',
  '11\u201D Olympic Double',
  '11\u201D Premier Single',
  '12\u201D Channel Mixer Amp',
  '12\u201D Channel Mixer',
  '12\u201D Evans Double Velum',
  '12\u201D GLS Double Velum',
  '12\u201D Single Velum',
  '12\u201D GLS Double Velum',
  '12\u201D GLS Naked Speaker',
  '12\u201D Naked Speaker',
  '12\u201D Remo Double Velum',
  '12\u201D Single Velum',
  '12V Battery Rechargeable',
];

/// A ready-to-import CSV template pre-filled with the store's stock sheet:
/// every item name is present with blank Price/Qty cells to fill in. The
/// exact header strings are accepted (aliases like "Qty" are tolerated by
/// the parser), so the client's original sheet imports as-is too.
String buildImportTemplateCsv() {
  final rows = <List<String>>[
    kImportTemplateHeaders,
    for (final item in kStarterItems)
      [item, '', '', '', '', '', '', '', '', '', ''],
  ];
  return const ListToCsvConverter().convert(rows);
}
