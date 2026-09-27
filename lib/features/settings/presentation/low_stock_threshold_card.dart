import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';

/// Editable global low-stock threshold — products at or below this quantity
/// (and without a reorder level of their own) are flagged on the Dashboard.
/// Shown only to users with the `systemConfig` permission.
class LowStockThresholdCard extends ConsumerWidget {
  const LowStockThresholdCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final threshold = ref.watch(lowStockThresholdProvider);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAB308).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFCA8A04),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Low stock alerts',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Products at or below this quantity are flagged on the '
                        'Dashboard. Products with their own reorder level use '
                        'that instead.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _editThreshold(context, ref),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 12),
            threshold.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (error, _) => Text(
                'Could not load the threshold: $error',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              data: (value) => _ThresholdRow(value: value),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editThreshold(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final current = await ref.read(lowStockThresholdProvider.future);
    if (!context.mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ThresholdDialog(initial: current),
    );
    if (saved != true || !context.mounted) return;
    ref.invalidate(lowStockThresholdProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Low stock threshold saved.'),
          backgroundColor: Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

String formatThreshold(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

class _ThresholdRow extends StatelessWidget {
  const _ThresholdRow({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_outlined, size: 16, color: Color(0xFFCA8A04)),
          const SizedBox(width: 8),
          const SizedBox(
            width: 80,
            child: Text(
              'Threshold',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${formatThreshold(value)} units or fewer',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThresholdDialog extends ConsumerStatefulWidget {
  const _ThresholdDialog({required this.initial});

  final double initial;

  @override
  ConsumerState<_ThresholdDialog> createState() => _ThresholdDialogState();
}

class _ThresholdDialogState extends ConsumerState<_ThresholdDialog> {
  late final _controller = TextEditingController(
    text: formatThreshold(widget.initial),
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit low stock threshold'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Alert at units or fewer',
                helperText:
                    'Applies to products without their own reorder level',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final value = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (value == null || value < 0) {
      setState(() => _error = 'Enter a number of 0 or more.');
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(() => _error = 'Not signed in.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(settingsRepositoryProvider)
          .saveLowStockThreshold(value, actingUserId: user.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
