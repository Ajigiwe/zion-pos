import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';
import 'package:instrument_pos/features/audit/presentation/audit_providers.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/auth/presentation/user_providers.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/presentation/receipt_print_service.dart';
import 'package:instrument_pos/features/settings/data/settings_repository.dart';
import 'package:instrument_pos/features/settings/domain/printer_settings.dart';
import 'package:instrument_pos/features/settings/presentation/printer_settings_card.dart';
import 'package:instrument_pos/features/settings/presentation/printer_settings_providers.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';
import 'package:printing/printing.dart';

import 'test_users.dart';

class _FakePrinterSettingsRepository extends Fake implements SettingsRepository {
  PrinterSettings settings = const PrinterSettings();
  String? lastUserId;

  @override
  Future<PrinterSettings> loadPrinterSettings() async => settings;

  @override
  Stream<PrinterSettings> watchPrinterSettings() => Stream.value(settings);

  @override
  Future<void> savePrinterSettings(
    PrinterSettings printerSettings, {
    required String actingUserId,
  }) async {
    settings = printerSettings;
    lastUserId = actingUserId;
  }
}

class _FakeReceiptPrintService implements ReceiptPrintService {
  int printCount = 0;
  String? lastPrintedName;

  @override
  Future<bool> printPdf(dynamic bytes, {required String name}) async {
    printCount++;
    lastPrintedName = name;
    return true;
  }
}

void main() {
  group('PrinterSettings domain model', () {
    test('default usesSystemDefault is true and directPrinting is true', () {
      const p = PrinterSettings();
      expect(p.usesSystemDefault, isTrue);
      expect(p.directPrinting, isTrue);
      expect(p.selectedPrinterUrl, isNull);
    });

    test('copyWith updates fields accurately', () {
      const p = PrinterSettings();
      final updated = p.copyWith(
        selectedPrinterUrl: 'win://POS-80',
        selectedPrinterName: 'POS-80 Thermal',
        directPrinting: false,
      );
      expect(updated.usesSystemDefault, isFalse);
      expect(updated.selectedPrinterUrl, 'win://POS-80');
      expect(updated.selectedPrinterName, 'POS-80 Thermal');
      expect(updated.directPrinting, isFalse);
    });
  });

  group('PrinterSettingsCard widget', () {
    testWidgets('renders direct printing switch, printer options, and prints test receipt', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeRepo = _FakePrinterSettingsRepository();
      final fakePrintService = _FakeReceiptPrintService();
      final user = testUser(id: 'u1', role: 'OWNER');

      const dummyPrinters = [
        Printer(
          url: 'win://POS80',
          name: 'POS-80 Thermal Receipt',
          model: 'Xprinter 80mm',
          isDefault: true,
          isAvailable: true,
        ),
        Printer(
          url: 'win://PDF',
          name: 'Microsoft Print to PDF',
          isDefault: false,
          isAvailable: true,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(user),
            settingsRepositoryProvider.overrideWithValue(fakeRepo),
            receiptPrintServiceProvider.overrideWithValue(fakePrintService),
            connectedPrintersProvider.overrideWith((ref) async => dummyPrinters),
            auditLogsProvider.overrideWith((ref) => Stream.value(const <AuditEntry>[])),
            usersProvider.overrideWith((ref) => Stream.value([user])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PrinterSettingsCard(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Receipt Printers & Hardware'), findsOneWidget);
      expect(find.text('Instant Direct Thermal Printing'), findsOneWidget);
      expect(find.text('System Default Printer'), findsOneWidget);
      expect(find.text('POS-80 Thermal Receipt'), findsOneWidget);
      expect(find.text('Microsoft Print to PDF'), findsOneWidget);
      expect(find.text('Print Test Receipt'), findsOneWidget);

      // Select POS-80 Thermal printer
      await tester.tap(find.text('POS-80 Thermal Receipt'));
      await tester.pumpAndSettle();

      expect(fakeRepo.settings.selectedPrinterUrl, 'win://POS80');
      expect(fakeRepo.settings.selectedPrinterName, 'POS-80 Thermal Receipt');
      expect(fakeRepo.lastUserId, 'u1');

      // Toggle direct printing
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(fakeRepo.settings.directPrinting, isFalse);

      // Tap Print Test Receipt
      await tester.tap(find.text('Print Test Receipt'));
      await tester.pumpAndSettle();

      expect(fakePrintService.printCount, 1);
      expect(fakePrintService.lastPrintedName, 'Receipt TEST-001');
    });
  });
}
