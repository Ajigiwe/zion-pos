import 'package:flutter/material.dart';

/// Predefined color preset choice for the POS application theme.
class ThemeColorPreset {
  const ThemeColorPreset({
    required this.id,
    required this.name,
    required this.color,
    required this.description,
  });

  final String id;
  final String name;
  final Color color;
  final String description;
}

/// Curated color palettes matching high-end POS design systems.
const List<ThemeColorPreset> kThemeColorPresets = [
  ThemeColorPreset(
    id: 'emerald',
    name: 'Forest Emerald',
    color: Color(0xFF16A34A),
    description: 'Classic trusted POS retail green',
  ),
  ThemeColorPreset(
    id: 'sapphire',
    name: 'Ocean Sapphire',
    color: Color(0xFF0284C7),
    description: 'Modern vibrant digital blue',
  ),
  ThemeColorPreset(
    id: 'amethyst',
    name: 'Royal Amethyst',
    color: Color(0xFF7C3AED),
    description: 'Sophisticated deep purple & violet',
  ),
  ThemeColorPreset(
    id: 'amber',
    name: 'Sunset Amber',
    color: Color(0xFFEA580C),
    description: 'Energetic warm orange & amber',
  ),
  ThemeColorPreset(
    id: 'teal',
    name: 'Midnight Teal',
    color: Color(0xFF0D9488),
    description: 'Clean balanced cyan & teal',
  ),
  ThemeColorPreset(
    id: 'ruby',
    name: 'Crimson Ruby',
    color: Color(0xFFE11D48),
    description: 'Bold elegant ruby red',
  ),
  ThemeColorPreset(
    id: 'slate',
    name: 'Monochrome Slate',
    color: Color(0xFF475569),
    description: 'Minimalist neutral executive slate',
  ),
];

const Color kDefaultSeedColor = Color(0xFF16A34A);

/// Holds application theme and color customization configuration.
class AppThemeSettings {
  const AppThemeSettings({
    this.themeMode = ThemeMode.light,
    this.primaryColor = kDefaultSeedColor,
    this.presetId = 'emerald',
  });

  final ThemeMode themeMode;
  final Color primaryColor;
  final String presetId;

  AppThemeSettings copyWith({
    ThemeMode? themeMode,
    Color? primaryColor,
    String? presetId,
  }) {
    return AppThemeSettings(
      themeMode: themeMode ?? this.themeMode,
      primaryColor: primaryColor ?? this.primaryColor,
      presetId: presetId ?? this.presetId,
    );
  }

  /// Serializes primary color as 8-digit hex string (e.g. `0xFF16A34A`).
  String get primaryColorHex {
    return '0x${primaryColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }

  /// Parses an 8-digit hex string or returns default.
  static Color parseColorHex(String? hex) {
    if (hex == null || hex.isEmpty) return kDefaultSeedColor;
    try {
      final clean = hex.replaceAll('#', '').replaceAll('0x', '');
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      } else if (clean.length == 8) {
        return Color(int.parse(clean, radix: 16));
      }
    } catch (_) {}
    return kDefaultSeedColor;
  }

  /// Serializes ThemeMode to string.
  String get themeModeString {
    switch (themeMode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.light:
        return 'light';
    }
  }

  /// Parses ThemeMode from string.
  static ThemeMode parseThemeMode(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppThemeSettings &&
          runtimeType == other.runtimeType &&
          themeMode == other.themeMode &&
          primaryColor.toARGB32() == other.primaryColor.toARGB32() &&
          presetId == other.presetId;

  @override
  int get hashCode =>
      themeMode.hashCode ^ primaryColor.toARGB32().hashCode ^ presetId.hashCode;
}

abstract class ThemeSettingKeys {
  static const themeMode = 'theme_mode';
  static const themeColor = 'theme_color';
  static const themePreset = 'theme_preset';

  static const allKeys = [themeMode, themeColor, themePreset];
}
