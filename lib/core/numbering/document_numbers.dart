import 'package:drift/drift.dart';
import 'package:instrument_pos/core/database/workstation_config.dart';

/// Scope applied to document numbers issued by this station.
///
/// Client stations get their own segment (`SA-K7F2-00001`) so a terminal that
/// works offline can never hand out a receipt the host already issued. The
/// host and standalone stations keep the classic `SA-00001` shape, which
/// keeps existing documents and reports intact.
String documentNumberPrefix(String prefix) {
  final config = WorkstationConfig.current;
  if (config.isClient && config.stationCode.isNotEmpty) {
    return '$prefix-${config.stationCode}';
  }
  return prefix;
}

/// Next free document number in [column], e.g. `SA-K7F2-00042`.
///
/// [table] and [column] are raw SQL names (`sales`, `receipt_number`) —
/// SQLite silently treats a misspelled double-quoted identifier as a string
/// literal, which would hand every caller the same number.
Future<String> nextDocumentNumber(
  DatabaseConnectionUser db, {
  required String table,
  required String column,
  required String prefix,
}) async {
  final scoped = documentNumberPrefix(prefix);
  // SQLite falls back to treating an unknown double-quoted identifier as a
  // string literal, which would make this query "succeed" with a constant
  // and hand out the first number forever. Verify the column exists first.
  final columns = await db
      .customSelect('PRAGMA table_info("$table")')
      .get();
  final known = columns.map((row) => row.data['name']).toSet();
  if (!known.contains(column)) {
    throw ArgumentError.value(column, 'column', 'not a column of "$table"');
  }
  final rows = await db
      .customSelect(
        'SELECT "$column" AS n FROM "$table" '
        "WHERE \"$column\" LIKE ? "
        'ORDER BY length("$column") DESC, "$column" DESC LIMIT 1',
        variables: [Variable.withString('$scoped-%')],
      )
      .get();

  var next = 1;
  if (rows.isNotEmpty) {
    final value = rows.first.data['n'] as String?;
    final match = value == null ? null : RegExp(r'(\d+)$').firstMatch(value);
    if (match != null) {
      next = int.parse(match.group(1)!) + 1;
    }
  }
  return '$scoped-${next.toString().padLeft(5, '0')}';
}
