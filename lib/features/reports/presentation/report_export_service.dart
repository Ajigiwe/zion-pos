import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// Exports report CSVs through the native save dialog. Abstract so widget
/// tests can fake it (same seam as StockSheetService).
abstract class ReportExportService {
  /// Writes [contents] through a save dialog. False when cancelled.
  Future<bool> saveCsv(String contents, {required String suggestedName});
}

class DesktopReportExportService implements ReportExportService {
  static const _csvType = XTypeGroup(
    label: 'CSV',
    extensions: ['csv'],
    mimeTypes: ['text/csv'],
  );

  @override
  Future<bool> saveCsv(String contents, {required String suggestedName}) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [_csvType],
    );
    if (location == null) return false;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.csv')) path = '$path.csv';
    await File(path).writeAsString(contents);
    return true;
  }
}
