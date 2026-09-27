import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';
import 'package:instrument_pos/features/audit/presentation/audit_providers.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/auth/presentation/user_providers.dart';
import 'package:instrument_pos/features/settings/data/settings_repository.dart';
import 'package:instrument_pos/features/settings/domain/app_theme_settings.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';
import 'package:instrument_pos/features/settings/presentation/theme_settings_card.dart';
import 'package:instrument_pos/features/settings/presentation/theme_settings_providers.dart';

import 'test_users.dart';

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  AppThemeSettings savedSettings = const AppThemeSettings();
  String? lastUserId;

  @override
  Future<AppThemeSettings> loadThemeSettings() async => savedSettings;

  @override
  Stream<AppThemeSettings> watchThemeSettings() => Stream.value(savedSettings);

  @override
  Future<void> saveThemeSettings(
    AppThemeSettings themeSettings, {
    required String actingUserId,
  }) async {
    savedSettings = themeSettings;
    lastUserId = actingUserId;
  }
}

void main() {
  group('AppThemeSettings domain logic', () {
    test('serializes and parses hex colors correctly', () {
      const color = Color(0xFF0284C7);
      const settings = AppThemeSettings(primaryColor: color);
      expect(settings.primaryColorHex, '0xFF0284C7');

      expect(AppThemeSettings.parseColorHex('0xFF0284C7'), color);
      expect(AppThemeSettings.parseColorHex('#0284C7'), color);
      expect(AppThemeSettings.parseColorHex('0284C7'), color);
      expect(AppThemeSettings.parseColorHex(null), kDefaultSeedColor);
    });

    test('serializes and parses ThemeMode correctly', () {
      expect(const AppThemeSettings(themeMode: ThemeMode.dark).themeModeString, 'dark');
      expect(const AppThemeSettings(themeMode: ThemeMode.light).themeModeString, 'light');
      expect(const AppThemeSettings(themeMode: ThemeMode.system).themeModeString, 'system');

      expect(AppThemeSettings.parseThemeMode('dark'), ThemeMode.dark);
      expect(AppThemeSettings.parseThemeMode('light'), ThemeMode.light);
      expect(AppThemeSettings.parseThemeMode('system'), ThemeMode.system);
      expect(AppThemeSettings.parseThemeMode(null), ThemeMode.light);
    });
  });

  group('ThemeSettingsCard UI Widget', () {
    testWidgets('renders theme modes, color presets, live preview, and switches modes', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeRepo = _FakeSettingsRepository();
      final user = testUser(id: 'u1', role: 'OWNER');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(user),
            settingsRepositoryProvider.overrideWithValue(fakeRepo),
            auditLogsProvider.overrideWith(
              (ref) => Stream.value(const <AuditEntry>[]),
            ),
            usersProvider.overrideWith((ref) => Stream.value(<User>[user])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ThemeSettingsCard(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Headers & Options
      expect(find.text('Appearance & Themes'), findsOneWidget);
      expect(find.text('Light Mode'), findsOneWidget);
      expect(find.text('Dark Mode'), findsOneWidget);
      expect(find.text('System Default'), findsOneWidget);
      expect(find.text('Forest Emerald'), findsOneWidget);
      expect(find.text('Ocean Sapphire'), findsOneWidget);
      expect(find.text('Royal Amethyst'), findsOneWidget);
      expect(find.text('LIVE PREVIEW'), findsOneWidget);

      // Tap Dark Mode
      await tester.tap(find.text('Dark Mode'));
      await tester.pumpAndSettle();

      expect(fakeRepo.savedSettings.themeMode, ThemeMode.dark);
      expect(fakeRepo.lastUserId, 'u1');

      // Tap Ocean Sapphire
      await tester.tap(find.text('Ocean Sapphire'));
      await tester.pumpAndSettle();

      expect(fakeRepo.savedSettings.presetId, 'sapphire');
      expect(fakeRepo.savedSettings.primaryColor, const Color(0xFF0284C7));

      // Tap Reset Defaults
      await tester.tap(find.text('Reset Defaults'));
      await tester.pumpAndSettle();

      expect(fakeRepo.savedSettings.themeMode, ThemeMode.light);
      expect(fakeRepo.savedSettings.presetId, 'emerald');
    });
  });
}
