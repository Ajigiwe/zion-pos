import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';

/// Editable shop identity (name, address, phone) — the letterhead printed on
/// receipts. Shown only to users with the `systemConfig` permission.
class StoreProfileCard extends ConsumerWidget {
  const StoreProfileCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final store = ref.watch(storeInfoControllerProvider);

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
                    color: const Color(0xFF0284C7).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    color: Color(0xFF0284C7),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Store details',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Name, address and phone printed on receipts.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => showStoreProfileDialog(context, ref),
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
            _DetailRow(
              icon: Icons.business_outlined,
              label: 'Name',
              value: store.name,
            ),
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.place_outlined,
              label: 'Address',
              value: store.address.isEmpty ? '—' : store.address,
            ),
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: store.phone.isEmpty ? '—' : store.phone,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

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
          Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
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

/// Opens the store-details dialog and saves on confirmation.
Future<void> showStoreProfileDialog(BuildContext context, WidgetRef ref) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return;
  final store = ref.read(storeInfoControllerProvider);
  final messenger = ScaffoldMessenger.of(context);
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => _StoreProfileDialog(initial: store),
  );
  if (saved != true || !context.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Store details saved.'),
        backgroundColor: Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

class _StoreProfileDialog extends ConsumerStatefulWidget {
  const _StoreProfileDialog({required this.initial});

  final StoreInfo initial;

  @override
  ConsumerState<_StoreProfileDialog> createState() =>
      _StoreProfileDialogState();
}

class _StoreProfileDialogState extends ConsumerState<_StoreProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.initial.name);
  late final _addressController = TextEditingController(
    text: widget.initial.address,
  );
  late final _phoneController = TextEditingController(
    text: widget.initial.phone,
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit store details'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Store name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Store name is required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  helperText: 'As printed under the store name on receipts',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
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
          child: Text(_saving ? 'Saving…' : 'Save details'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final user = ref.read(currentUserProvider);
    if (user == null) {
      if (mounted) setState(() => _error = 'Not signed in.');
      return;
    }
    try {
      await ref
          .read(storeInfoControllerProvider.notifier)
          .save(
            StoreInfo(
              name: _nameController.text.trim(),
              address: _addressController.text.trim(),
              phone: _phoneController.text.trim(),
            ),
            actingUserId: user.id,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
