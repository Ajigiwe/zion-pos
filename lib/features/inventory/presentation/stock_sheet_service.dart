import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:printing/printing.dart';

/// Print/save operations for the stock-count sheet. Abstract so widget tests
/// can fake them without opening the native print or save dialogs.
abstract class StockSheetService {
  /// Opens the native print dialog. Works without a physical printer via
  /// "Microsoft Print to PDF". True when the job was sent.
  Future<bool> printPdf(Uint8List bytes, {required String name});

  /// Writes the PDF through a save dialog. False when cancelled.
  Future<bool> savePdf(Uint8List bytes, {required String suggestedName});
}

class DesktopStockSheetService implements StockSheetService {
  static const _pdf = XTypeGroup(label: 'PDF', extensions: ['pdf']);

  @override
  Future<bool> printPdf(Uint8List bytes, {required String name}) async {
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
    return true;
  }

  @override
  Future<bool> savePdf(Uint8List bytes, {required String suggestedName}) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [_pdf],
    );
    if (location == null) return false;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.pdf')) path = '$path.pdf';
    await File(path).writeAsBytes(bytes);
    return true;
  }
}
