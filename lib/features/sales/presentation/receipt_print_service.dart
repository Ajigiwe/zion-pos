import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/domain/receipt_document.dart';
import 'package:instrument_pos/features/settings/presentation/printer_settings_providers.dart';
import 'package:printing/printing.dart';

/// Print operations for sale receipts. Abstract so widget tests can fake it
/// without opening the native print dialog.
abstract class ReceiptPrintService {
  /// Opens the native print dialog or directly prints. Works without a physical printer via
  /// "Microsoft Print to PDF". True when the job was sent.
  Future<bool> printPdf(Uint8List bytes, {required String name});
}

class DesktopReceiptPrintService implements ReceiptPrintService {
  DesktopReceiptPrintService([this._ref]);

  final Ref? _ref;

  @override
  Future<bool> printPdf(Uint8List bytes, {required String name}) async {
    try {
      final settings = _ref?.read(printerSettingsControllerProvider);
      final printers = await Printing.listPrinters();
      Printer? target;

      // 1. Look for user-selected printer if configured
      if (settings != null && !settings.usesSystemDefault) {
        for (final printer in printers) {
          if ((settings.selectedPrinterUrl != null &&
                  printer.url == settings.selectedPrinterUrl) ||
              (settings.selectedPrinterName != null &&
                  printer.name == settings.selectedPrinterName)) {
            target = printer;
            break;
          }
        }
      }

      // 2. Otherwise find the operating system default printer
      if (target == null) {
        for (final printer in printers) {
          if (printer.isDefault) {
            target = printer;
            break;
          }
        }
      }

      target ??= printers.isNotEmpty ? printers.first : null;

      final direct = settings?.directPrinting ?? true;

      if (target != null && direct) {
        final success = await Printing.directPrintPdf(
          printer: target,
          onLayout: (_) async => bytes,
          name: name,
        );
        if (success) return true;
      }
    } catch (_) {
      // Fallback if direct printing is unsupported
    }
    return await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
  }
}

/// Native receipt printing through the Windows print subsystem (faked in widget tests).
final receiptPrintServiceProvider = Provider<ReceiptPrintService>(
  (ref) => DesktopReceiptPrintService(ref),
);

/// Builds and sends a receipt to the printer. Returns false when nothing was
/// printed (e.g. the dialog was cancelled).
Future<bool> printReceipt(
  WidgetRef ref, {
  required ReceiptContent content,
}) async {
  final bytes = await buildReceiptPdf(content: content);
  return ref
      .read(receiptPrintServiceProvider)
      .printPdf(bytes, name: 'Receipt ${content.receiptNumber}');
}
