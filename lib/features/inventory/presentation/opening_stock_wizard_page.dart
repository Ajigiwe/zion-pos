import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/inventory/presentation/inventory_providers.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';

/// Initial setup wizard (§21): assign starting quantities to products.
/// Creates OPENING_STOCK ledger movements — never touches stock directly.
class OpeningStockWizardPage extends ConsumerStatefulWidget {
  const OpeningStockWizardPage({super.key});

  @override
  ConsumerState<OpeningStockWizardPage> createState() =>
      _OpeningStockWizardPageState();
}

class _OpeningStockWizardPageState
    extends ConsumerState<OpeningStockWizardPage> {
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products =
        ref.watch(productsProvider('')).value ?? const <ProductWithStock>[];

    // Opening stock applies to products without stock on the ledger.
    final openProducts = products.where((item) => item.stock <= 0).toList();
    _ensureControllers(openProducts);

    final entries = _validEntries(openProducts);

    return Scaffold(
      appBar: AppBar(title: const Text('Opening Stock')),
      body: openProducts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text('No products need opening stock'),
                  const SizedBox(height: 4),
                  Text(
                    'Every product already has stock on the ledger.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Enter the starting quantity for each product. Only products with '
                    'zero stock are listed; you can always add stock later.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    itemCount: openProducts.length,
                    itemBuilder: (context, index) {
                      final item = openProducts[index];
                      return _OpeningRow(
                        item: item,
                        controller: _controllers[item.product.id]!,
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entries.isEmpty
                                ? 'No quantities entered'
                                : '${entries.length} product(s) · '
                                      '${entries.values.fold<int>(0, (sum, qty) => sum + qty)} units',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _saving || entries.isEmpty
                              ? null
                              : _commit,
                          icon: const Icon(Icons.check),
                          label: const Text('Record opening stock'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _ensureControllers(List<ProductWithStock> products) {
    final ids = products.map((item) => item.product.id).toSet();
    _controllers.removeWhere((id, _) => !ids.contains(id));
    for (final item in products) {
      _controllers.putIfAbsent(item.product.id, TextEditingController.new);
    }
  }

  /// productId -> opening quantity for rows with a positive whole number.
  Map<String, int> _validEntries(List<ProductWithStock> products) {
    final entries = <String, int>{};
    for (final item in products) {
      final text = _controllers[item.product.id]?.text.trim() ?? '';
      final value = int.tryParse(text);
      if (value != null && value > 0) entries[item.product.id] = value;
    }
    return entries;
  }

  Future<void> _commit() async {
    final entries = _validEntries(
      ref.read(productsProvider('')).value ?? const <ProductWithStock>[],
    );
    setState(() => _saving = true);
    try {
      final count = await ref
          .read(inventoryRepositoryProvider)
          .recordOpeningStock(
            entries,
            userId: ref.read(currentUserProvider)?.id,
          );
      if (mounted) Navigator.of(context).pop(count);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _OpeningRow extends StatelessWidget {
  const _OpeningRow({required this.item, required this.controller});

  final ProductWithStock item;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(product.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(product.sku),
      trailing: SizedBox(
        width: 140,
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Quantity',
            border: OutlineInputBorder(),
            isDense: true,
            suffixText: 'units',
          ),
        ),
      ),
    );
  }
}
