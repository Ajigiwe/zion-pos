import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/settings/domain/app_theme_settings.dart';
import 'package:instrument_pos/features/settings/presentation/theme_settings_providers.dart';

class ThemeSettingsCard extends ConsumerWidget {
  const ThemeSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeSettingsControllerProvider);
    final user = ref.watch(currentUserProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.palette_rounded,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appearance & Themes',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Customize dark mode, system brightness, and store brand colors.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                // Reset Button
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(themeSettingsControllerProvider.notifier).save(
                          const AppThemeSettings(),
                          actingUserId: user?.id ?? '',
                        );
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Reset Defaults'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 20),

            // Section 1: Theme Mode (Light / Dark / System)
            Text(
              'THEME MODE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildModeOption(
                  context: context,
                  title: 'Light Mode',
                  subtitle: 'Clean & daylight ready',
                  icon: Icons.light_mode_rounded,
                  selected: themeSettings.themeMode == ThemeMode.light,
                  onTap: () {
                    ref.read(themeSettingsControllerProvider.notifier).setThemeMode(
                          ThemeMode.light,
                          actingUserId: user?.id ?? '',
                        );
                  },
                ),
                const SizedBox(width: 12),
                _buildModeOption(
                  context: context,
                  title: 'Dark Mode',
                  subtitle: 'Low-glare night aesthetic',
                  icon: Icons.dark_mode_rounded,
                  selected: themeSettings.themeMode == ThemeMode.dark,
                  onTap: () {
                    ref.read(themeSettingsControllerProvider.notifier).setThemeMode(
                          ThemeMode.dark,
                          actingUserId: user?.id ?? '',
                        );
                  },
                ),
                const SizedBox(width: 12),
                _buildModeOption(
                  context: context,
                  title: 'System Default',
                  subtitle: 'Sync with OS brightness',
                  icon: Icons.brightness_auto_rounded,
                  selected: themeSettings.themeMode == ThemeMode.system,
                  onTap: () {
                    ref.read(themeSettingsControllerProvider.notifier).setThemeMode(
                          ThemeMode.system,
                          actingUserId: user?.id ?? '',
                        );
                  },
                ),
              ],
            ),
            const SizedBox(height: 26),

            // Section 2: Accent Color Palette
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ACCENT BRAND PALETTE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showCustomColorDialog(context, ref, user?.id ?? '', themeSettings.primaryColor),
                  icon: const Icon(Icons.colorize_rounded, size: 16),
                  label: const Text('Custom Hex Color'),
                  style: TextButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final preset in kThemeColorPresets)
                  _buildColorPresetTile(
                    context: context,
                    preset: preset,
                    selected: themeSettings.presetId == preset.id,
                    onTap: () {
                      ref.read(themeSettingsControllerProvider.notifier).setColorPreset(
                            preset,
                            actingUserId: user?.id ?? '',
                          );
                    },
                  ),
                if (themeSettings.presetId == 'custom')
                  _buildCustomColorTile(
                    context: context,
                    color: themeSettings.primaryColor,
                    selected: true,
                    onTap: () => _showCustomColorDialog(context, ref, user?.id ?? '', themeSettings.primaryColor),
                  ),
              ],
            ),
            const SizedBox(height: 26),

            // Section 3: Live Theme Preview Card
            Text(
              'LIVE PREVIEW',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 10),
            _buildLivePreview(context, themeSettings),
          ],
        ),
      ),
    );
  }

  Widget _buildModeOption({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withOpacity(0.08)
                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? theme.colorScheme.primary : const Color(0xFFCBD5E1),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? theme.colorScheme.primary
                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                        color: selected ? theme.colorScheme.primary : null,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorPresetTile({
    required BuildContext context,
    required ThemeColorPreset preset,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? preset.color.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? preset.color : const Color(0xFFE2E8F0),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: preset.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: preset.color.withOpacity(0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                preset.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomColorTile({
    required BuildContext context,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: const Icon(Icons.check, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Custom Color',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLivePreview(BuildContext context, AppThemeSettings settings) {
    final previewColor = settings.primaryColor;
    final isPreviewDark = settings.themeMode == ThemeMode.dark;
    final bgColor = isPreviewDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isPreviewDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isPreviewDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isPreviewDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Simulated Mini Sidebar
          SizedBox(
            width: 130,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.storefront_rounded, size: 15, color: previewColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'POS Till',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: previewColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.point_of_sale_outlined, size: 12, color: previewColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Register',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: previewColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 12, color: subtextColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Stock',
                            style: TextStyle(fontSize: 10, color: subtextColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Simulated Main Content Area
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Yamaha Pacifica 112V',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: previewColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'IN STOCK',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: previewColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Electric Guitar · SKU: GT-112V · Unit Price: GHS 2,450.00',
                    style: TextStyle(fontSize: 10, color: subtextColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                        label: const Text(
                          'Complete Sale',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: previewColor,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: Text(
                          'Hold Cart',
                          style: TextStyle(fontSize: 11, color: textColor),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCustomColorDialog(BuildContext context, WidgetRef ref, String userId, Color currentColor) {
    final hexController = TextEditingController(
      text: currentColor.toARGB32().toRadixString(16).substring(2).toUpperCase(),
    );
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Custom Accent Hex Color'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter a 6-digit RGB hex code (e.g. 16A34A or 0284C7):',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hexController,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixText: '# ',
                  hintText: '16A34A',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final parsed = AppThemeSettings.parseColorHex(hexController.text);
                ref.read(themeSettingsControllerProvider.notifier).setCustomColor(
                      parsed,
                      actingUserId: userId,
                    );
                Navigator.of(ctx).pop();
              },
              child: const Text('Apply Color'),
            ),
          ],
        );
      },
    );
  }
}
