import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

pw.Font? _robotoRegular;
pw.Font? _robotoBold;

/// Loads the bundled Roboto (covers Unicode like the inch marks in item
/// names, which the PDF base-14 fonts cannot encode), cached after the first
/// call. Falls back to Helvetica if the asset is unavailable.
Future<pw.Font?> _loadFont(String asset) async {
  try {
    final data = await rootBundle.load(asset);
    return pw.Font.ttf(data);
  } catch (_) {
    return null;
  }
}

Future<pw.Font> pdfRegularFont() async => _robotoRegular ??=
    await _loadFont('assets/fonts/roboto-regular.ttf') ?? pw.Font.helvetica();

Future<pw.Font> pdfBoldFont() async => _robotoBold ??=
    await _loadFont('assets/fonts/roboto-bold.ttf') ?? pw.Font.helveticaBold();
