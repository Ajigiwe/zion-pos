import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';
import 'package:instrument_pos/features/audit/presentation/audit_providers.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/auth/presentation/user_management_page.dart';
import 'package:instrument_pos/features/auth/presentation/user_providers.dart';
import 'package:instrument_pos/features/sales/domain/receipt_customization.dart';
import 'package:instrument_pos/features/settings/data/settings_repository.dart';
import 'package:instrument_pos/features/settings/domain/app_theme_settings.dart';
import 'package:instrument_pos/features/settings/domain/printer_settings.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';
import 'package:instrument_pos/features/settings/domain/network_settings.dart';

import 'test_users.dart';

class _FakeSettingsRepository implements SettingsRepository {
  final saved = <StoreInfo>[];
  String? actingUserId;
  double savedThreshold = -1;
  double threshold = 5;

  @override
  Future<StoreInfo> loadStoreInfo() async => kStoreInfo;

  @override
  Stream<StoreInfo> watchStoreInfo() => Stream.value(kStoreInfo);

  @override
  Future<void> updateStoreInfo(
    StoreInfo info, {
    required String actingUserId,
  }) async {
    saved.add(info);
    this.actingUserId = actingUserId;
  }

  @override
  Future<double> loadLowStockThreshold() async => threshold;

  @override
  Future<void> saveLowStockThreshold(
    double value, {
    required String actingUserId,
  }) async {
    savedThreshold = value;
    threshold = value;
    this.actingUserId = actingUserId;
  }

  @override
  Future<ReceiptCustomization> loadReceiptCustomization() async =>
      const ReceiptCustomization();

  @override
  Stream<ReceiptCustomization> watchReceiptCustomization() =>
      Stream.value(const ReceiptCustomization());

  @override
  Future<void> saveReceiptCustomization(
    ReceiptCustomization customization, {
    required String actingUserId,
  }) async {
    this.actingUserId = actingUserId;
  }

  @override
  Future<AppThemeSettings> loadThemeSettings() async =>
      const AppThemeSettings();

  @override
  Stream<AppThemeSettings> watchThemeSettings() =>
      Stream.value(const AppThemeSettings());

  @override
  Future<void> saveThemeSettings(
    AppThemeSettings themeSettings, {
    required String actingUserId,
  }) async {
    this.actingUserId = actingUserId;
  }

  @override
  Future<PrinterSettings> loadPrinterSettings() async =>
      const PrinterSettings();

  @override
  Stream<PrinterSettings> watchPrinterSettings() =>
      Stream.value(const PrinterSettings());

  @override
  Future<void> savePrinterSettings(
    PrinterSettings printerSettings, {
    required String actingUserId,
  }) async {
    this.actingUserId = actingUserId;
  }

  @override
  Future<NetworkSettings> loadNetworkSettings() async => const NetworkSettings();

  @override
  Stream<NetworkSettings> watchNetworkSettings() =>
      Stream.value(const NetworkSettings());

  @override
  Future<void> saveNetworkSettings(
    NetworkSettings networkSettings, {
    required String actingUserId,
  }) async {
    this.actingUserId = actingUserId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget wrap(User current) => ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(current),
      auditLogsProvider.overrideWith(
        (ref) => Stream.value(const <AuditEntry>[]),
      ),
      usersProvider.overrideWith((ref) => Stream.value(<User>[current])),
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
    ],
    child: const MaterialApp(home: Scaffold(body: SettingsPage())),
  );

  void useDesktopViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('owner edits the store details and they persist', (tester) async {
    useDesktopViewport(tester);
    final repo = _FakeSettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(testUser(id: 'u1')),
          auditLogsProvider.overrideWith(
            (ref) => Stream.value(const <AuditEntry>[]),
          ),
          usersProvider.overrideWith(
            (ref) => Stream.value(<User>[testUser(id: 'u1')]),
          ),
          settingsRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();

    // The card shows the current letterhead and an Edit action.
    await tester.scrollUntilVisible(
      find.text('Database backup'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Database backup'), findsOneWidget);
    expect(find.text('Export backup…'), findsOneWidget);
    expect(find.text('Restore from backup…'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Store details'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Store details'), findsOneWidget);
    expect(find.text('Zion Musical Centre'), findsOneWidget);
    expect(find.text('Market Circle - Tarkwa'), findsOneWidget);
    expect(find.text(kStoreInfo.phone), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Edit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit').first);
    await tester.pumpAndSettle();

    // Change the name; the address and phone are prefilled.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Store name *'),
      'Zion Music Hub',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save details'));
    await tester.pumpAndSettle();

    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.name, 'Zion Music Hub');
    expect(repo.saved.single.address, 'Market Circle - Tarkwa');
    expect(repo.actingUserId, 'u1');
    expect(find.text('Store details saved.'), findsOneWidget);
    // The card now reflects the saved profile.
    expect(find.text('Zion Music Hub'), findsOneWidget);
  });

  testWidgets('store name is required', (tester) async {
    useDesktopViewport(tester);
    await tester.pumpWidget(wrap(testUser(id: 'u1')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Store name *'),
      '   ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save details'));
    await tester.pumpAndSettle();

    expect(find.text('Store name is required'), findsOneWidget);
    expect(find.text('Store details saved.'), findsNothing);
  });

  testWidgets('cashiers and managers never see the store details card', (
    tester,
  ) async {
    useDesktopViewport(tester);
    for (final role in ['CASHIER', 'MANAGER', 'INVENTORY_MANAGER']) {
      await tester.pumpWidget(wrap(testUser(id: 'u2', role: role)));
      await tester.pumpAndSettle();
      expect(find.text('Store details'), findsNothing);
      expect(find.text('Database backup'), findsNothing);
      expect(find.text('Edit'), findsNothing);
    }
  });

  testWidgets('owner edits the low stock threshold and it persists', (
    tester,
  ) async {
    useDesktopViewport(tester);
    final repo = _FakeSettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(testUser()),
          auditLogsProvider.overrideWith(
            (ref) => Stream.value(const <AuditEntry>[]),
          ),
          usersProvider.overrideWith((ref) => Stream.value(<User>[testUser()])),
          settingsRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Low stock alerts'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Low stock alerts'), findsOneWidget);
    expect(find.text('5 units or fewer'), findsOneWidget);

    final lowStockEditButton = find.descendant(
      of: find.ancestor(
        of: find.text('Low stock alerts'),
        matching: find.byType(Card),
      ),
      matching: find.text('Edit'),
    );
    await tester.ensureVisible(lowStockEditButton);
    await tester.pumpAndSettle();
    await tester.tap(lowStockEditButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Alert at units or fewer'),
      '8',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.savedThreshold, 8);
    expect(repo.actingUserId, testUser().id);
    expect(find.text('8 units or fewer'), findsOneWidget);
    expect(find.text('Low stock threshold saved.'), findsOneWidget);
  });
}
