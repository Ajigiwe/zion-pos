import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/features/settings/domain/printer_settings.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';
import 'package:printing/printing.dart';

/// Manages reactive active printer selection and direct printing toggles.
class PrinterSettingsController extends Notifier<PrinterSettings> {
  @override
  PrinterSettings build() => const PrinterSettings();

  Future<void> loadFromDb() async {
    try {
      state = await ref.read(settingsRepositoryProvider).loadPrinterSettings();
    } catch (_) {
      // Fallback to default
    }
  }

  Future<void> save(
    PrinterSettings next, {
    required String actingUserId,
  }) async {
    state = next;
    try {
      await ref
          .read(settingsRepositoryProvider)
          .savePrinterSettings(next, actingUserId: actingUserId);
    } catch (_) {}
  }

  Future<void> setPrinter({
    required String? url,
    required String? name,
    required String actingUserId,
  }) async {
    final next = state.copyWith(
      selectedPrinterUrl: url,
      selectedPrinterName: name,
    );
    await save(next, actingUserId: actingUserId);
  }

  Future<void> setDirectPrinting(
    bool direct, {
    required String actingUserId,
  }) async {
    final next = state.copyWith(directPrinting: direct);
    await save(next, actingUserId: actingUserId);
  }
}

final printerSettingsControllerProvider =
    NotifierProvider<PrinterSettingsController, PrinterSettings>(
      PrinterSettingsController.new,
    );

/// Queries all hardware and network printers detected by the operating system.
final connectedPrintersProvider = FutureProvider<List<Printer>>((ref) async {
  try {
    return await Printing.listPrinters();
  } catch (_) {
    return const <Printer>[];
  }
});
