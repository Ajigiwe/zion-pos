import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/features/settings/domain/app_theme_settings.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';

/// Manages reactive theme mode and color palette customization across the POS application.
class ThemeSettingsController extends Notifier<AppThemeSettings> {
  @override
  AppThemeSettings build() => const AppThemeSettings();

  Future<void> loadFromDb() async {
    try {
      state = await ref.read(settingsRepositoryProvider).loadThemeSettings();
    } catch (_) {
      // Fallback to default theme settings
    }
  }

  Future<void> save(
    AppThemeSettings next, {
    required String actingUserId,
  }) async {
    state = next;
    try {
      await ref
          .read(settingsRepositoryProvider)
          .saveThemeSettings(next, actingUserId: actingUserId);
    } catch (_) {}
  }

  Future<void> setThemeMode(
    ThemeMode mode, {
    required String actingUserId,
  }) async {
    final next = state.copyWith(themeMode: mode);
    await save(next, actingUserId: actingUserId);
  }

  Future<void> setColorPreset(
    ThemeColorPreset preset, {
    required String actingUserId,
  }) async {
    final next = state.copyWith(
      primaryColor: preset.color,
      presetId: preset.id,
    );
    await save(next, actingUserId: actingUserId);
  }

  Future<void> setCustomColor(
    Color color, {
    required String actingUserId,
  }) async {
    final next = state.copyWith(
      primaryColor: color,
      presetId: 'custom',
    );
    await save(next, actingUserId: actingUserId);
  }
}

final themeSettingsControllerProvider =
    NotifierProvider<ThemeSettingsController, AppThemeSettings>(
      ThemeSettingsController.new,
    );
