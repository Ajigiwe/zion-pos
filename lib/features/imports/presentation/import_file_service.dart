import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:instrument_pos/features/imports/domain/import_document.dart';

/// An uploaded import file: original name plus raw bytes.
class PickedImportFile {
  const PickedImportFile({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

/// File-system operations the Imports screen needs. Abstract so widget tests
/// can supply canned bytes without a real file dialog.
abstract class ImportFileService {
  /// Shows the open dialog for .csv/.xlsx files. Null when cancelled.
  Future<PickedImportFile?> pickFile();

  /// Writes the CSV template through a save dialog. False when cancelled.
  Future<bool> saveTemplate();
}

class DesktopImportFileService implements ImportFileService {
  static const _spreadsheet = XTypeGroup(
    label: 'Spreadsheet',
    extensions: ['csv', 'xlsx'],
  );
  static const _csv = XTypeGroup(label: 'CSV', extensions: ['csv']);

  @override
  Future<PickedImportFile?> pickFile() async {
    final file = await openFile(acceptedTypeGroups: const [_spreadsheet]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedImportFile(name: file.name, bytes: bytes);
  }

  @override
  Future<bool> saveTemplate() async {
    final location = await getSaveLocation(
      suggestedName: 'product-import-template.csv',
      acceptedTypeGroups: const [_csv],
    );
    if (location == null) return false;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.csv')) path = '$path.csv';
    await File(path).writeAsString(buildImportTemplateCsv());
    return true;
  }
}
