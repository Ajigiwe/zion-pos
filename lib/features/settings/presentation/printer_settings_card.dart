import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';
import 'package:instrument_pos/features/sales/presentation/receipt_print_service.dart';
import 'package:instrument_pos/features/settings/presentation/printer_settings_providers.dart';
import 'package:instrument_pos/features/settings/presentation/receipt_settings_providers.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';
import 'package:printing/printing.dart';

class PrinterSettingsCard extends ConsumerWidget {
  const PrinterSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final printerSettings = ref.watch(printerSettingsControllerProvider);
    final user = ref.watch(currentUserProvider);
    final printersAsync = ref.watch(connectedPrintersProvider);
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
                    Icons.print_rounded,
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
                        'Receipt Printers & Hardware',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Select connected POS printer, configure direct printing, and test receipt output.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                // Rescan Devices Button
                OutlinedButton.icon(
                  onPressed: () {
                    ref.invalidate(connectedPrintersProvider);
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Rescan'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 18),

            // Direct Printing Toggle
            Material(
              color: isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF8FAFC),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Instant Direct Thermal Printing',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Send receipts straight to the printer silently with 0 clicks after sale.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: printerSettings.directPrinting,
                      onChanged: (val) {
                        ref
                            .read(printerSettingsControllerProvider.notifier)
                            .setDirectPrinting(
                              val,
                              actingUserId: user?.id ?? '',
                            );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),

            // Printer Selection List
            Text(
              'CONNECTED PRINTERS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 10),

            printersAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Scanning for connected printers…',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFDC2626)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Failed to detect printers: $err',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              data: (printers) {
                return Column(
                  children: [
                    // System Default Choice
                    _buildPrinterOptionTile(
                      context: context,
                      name: 'System Default Printer',
                      url: null,
                      model: 'Uses the active Windows default printer',
                      isSystemDefaultBadge: true,
                      selected: printerSettings.usesSystemDefault,
                      onTap: () {
                        ref
                            .read(printerSettingsControllerProvider.notifier)
                            .setPrinter(
                              url: null,
                              name: null,
                              actingUserId: user?.id ?? '',
                            );
                      },
                    ),
                    const SizedBox(height: 8),

                    if (printers.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 20,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'No external printers detected. Plug in your USB/network receipt printer or use System Default.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final printer in printers) ...[
                        _buildPrinterOptionTile(
                          context: context,
                          name: printer.name,
                          url: printer.url,
                          model: printer.model ?? printer.location,
                          isSystemDefaultBadge: printer.isDefault,
                          selected:
                              printerSettings.selectedPrinterUrl ==
                                  printer.url ||
                              printerSettings.selectedPrinterName ==
                                  printer.name,
                          onTap: () {
                            ref
                                .read(
                                  printerSettingsControllerProvider.notifier,
                                )
                                .setPrinter(
                                  url: printer.url,
                                  name: printer.name,
                                  actingUserId: user?.id ?? '',
                                );
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                  ],
                );
              },
            ),

            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 18),

            // Print Test Receipt Action
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => _printTestReceipt(context, ref),
                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                  label: const Text('Print Test Receipt'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Sends an 80mm sample receipt to verify paper cutter, font clarity, and printer communication.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterOptionTile({
    required BuildContext context,
    required String name,
    required String? url,
    required String? model,
    required bool isSystemDefaultBadge,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withOpacity(0.08)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? colorScheme.primary : const Color(0xFFE2E8F0),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? colorScheme.primary
                  : (isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF94A3B8)),
              size: 20,
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.print_outlined,
              size: 20,
              color: selected
                  ? colorScheme.primary
                  : (isDark
                      ? const Color(0xFFCBD5E1)
                      : const Color(0xFF475569)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w600,
                            color: selected ? colorScheme.primary : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSystemDefaultBadge) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: const Text(
                            'OS DEFAULT',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (model != null && model.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      model,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _printTestReceipt(BuildContext context, WidgetRef ref) async {
    final store = ref.read(storeInfoControllerProvider);
    final customization = ref.read(receiptCustomizationControllerProvider);
    final user = ref.read(currentUserProvider);

    final sampleReceipt = ReceiptContent(
      store: store,
      receiptNumber: 'TEST-001',
      createdAt: DateTime.now(),
      cashierName: user?.displayName ?? 'Admin',
      customization: customization,
      totals: const SaleTotals(
        grossSubtotal: 0.0,
        discount: 0.0,
        taxIncluded: 0.0,
        total: 0.0,
      ),
      lines: const [
        (name: 'Thermal Printer Hardware Test', quantity: 1.0, unitPrice: 0.0),
        (name: 'Paper Feed & Calibration OK', quantity: 1.0, unitPrice: 0.0),
      ],
      payments: const [
        PaymentDraft(method: PaymentMethod.cash, amount: 0.0),
      ],
      change: 0.0,
    );

    try {
      final ok = await printReceipt(ref, content: sampleReceipt);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Test receipt sent to printer successfully!'
                  : 'Test print cancelled or completed.',
            ),
          ),
        );
      }
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to print test receipt: $err'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
