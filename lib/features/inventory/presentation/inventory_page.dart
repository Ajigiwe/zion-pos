import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/auth/domain/roles.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/inventory/data/inventory_repository.dart';
import 'package:instrument_pos/features/inventory/domain/movement_type_meta.dart';
import 'package:instrument_pos/features/inventory/domain/stock_sheet_document.dart';
import 'package:instrument_pos/features/inventory/presentation/inventory_providers.dart';
import 'package:instrument_pos/features/inventory/presentation/movement_type_style.dart';
import 'package:instrument_pos/features/inventory/presentation/opening_stock_wizard_page.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';
import 'package:instrument_pos/features/sales/presentation/barcode_scan_dialog.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final _searchController = TextEditingController();
  MovementType? _typeFilter;
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final movements = ref.watch(
      movementsProvider(MovementFilter(type: _typeFilter, search: _search)),
    );
    final products =
        ref.watch(productsProvider('')).value ?? const <ProductWithStock>[];
    final hasProducts = products.isNotEmpty;

    // Manual inventory actions are permission-controlled (§16, §31).
    final user = ref.watch(currentUserProvider);
    final role = user == null ? null : Role.fromStorage(user.role);
    final canControlStock = role?.can(Permission.inventoryControl) ?? false;
    final canAdjustStock = role?.can(Permission.stockAdjustment) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Inventory',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: hasProducts && canControlStock
                            ? () => _openOpeningStock()
                            : null,
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Opening stock…'),
                      ),
                      FilledButton.icon(
                        onPressed: hasProducts && canControlStock
                            ? () => _openAction(ManualMovementAction.add)
                            : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Add stock'),
                      ),
                      OutlinedButton.icon(
                        onPressed: hasProducts && canAdjustStock
                            ? () => _openAction(ManualMovementAction.adjust)
                            : null,
                        icon: const Icon(Icons.tune),
                        label: const Text('Adjust'),
                      ),
                      OutlinedButton.icon(
                        onPressed: hasProducts && canAdjustStock
                            ? () => _openAction(ManualMovementAction.damage)
                            : null,
                        icon: const Icon(Icons.report_problem_outlined),
                        label: const Text('Damage'),
                      ),
                      OutlinedButton.icon(
                        onPressed: hasProducts ? () => _openStockSheet() : null,
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Stock sheet'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Every change is a ledger movement — stock is never edited directly (§2.3).',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              SizedBox(
                width: 240,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Movement type',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<MovementType?>(
                      value: _typeFilter,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<MovementType?>(
                          value: null,
                          child: Text('All types'),
                        ),
                        for (final type in MovementType.values)
                          DropdownMenuItem<MovementType?>(
                            value: type,
                            child: Text(type.label),
                          ),
                      ],
                      onChanged: (value) => setState(() => _typeFilter = value),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _search = value.trim()),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_search.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                          tooltip: 'Scan Barcode / Item',
                          onPressed: () async {
                            final code = await BarcodeScanDialog.showForBarcode(context);
                            if (code != null && code.isNotEmpty) {
                              _searchController.text = code;
                              setState(() => _search = code);
                            }
                          },
                        ),
                      ],
                    ),
                    hintText: 'Search by product name, SKU or barcode…',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: movements.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Error: $error')),
            data: (items) => _MovementLedger(items: items),
          ),
        ),
      ],
    );
  }

  Future<void> _openOpeningStock() async {
    final recorded = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const OpeningStockWizardPage()),
    );
    if (recorded != null && recorded > 0 && mounted) {
      _showSnack('Opening stock recorded for $recorded product(s).');
    }
  }

  Future<void> _openAction(ManualMovementAction action) async {
    final result = await showStockActionDialog(
      context: context,
      ref: ref,
      action: action,
    );
    if (result != null && mounted) _showSnack(result);
  }

  Future<void> _openStockSheet() async {
    final products =
        ref.read(productsProvider('')).value ?? const <ProductWithStock>[];
    final store = ref.read(storeInfoControllerProvider);

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('Print stock sheet'),
              subtitle: Text(
                '${products.length} item(s) — native print dialog '
                '(Print to PDF works without a printer)',
              ),
              onTap: () => Navigator.pop(context, 'print'),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Save as PDF'),
              subtitle: const Text(
                'Writes the same sheet to a file for later printing',
              ),
              onTap: () => Navigator.pop(context, 'save'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    final bytes = await buildStockSheetPdf(
      store: store,
      products: products,
      now: DateTime.now(),
    );
    final service = ref.read(stockSheetServiceProvider);
    final bool ok;
    if (action == 'print') {
      ok = await service.printPdf(bytes, name: 'stock-count-sheet');
    } else {
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      ok = await service.savePdf(
        bytes,
        suggestedName:
            'stock-count-'
            '${now.year}-${two(now.month)}-${two(now.day)}.pdf',
      );
    }
    if (ok && mounted) {
      _showSnack(
        action == 'print'
            ? 'Stock sheet sent to the printer.'
            : 'Stock sheet saved as PDF.',
      );
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MovementLedger extends ConsumerWidget {
  const _MovementLedger({required this.items});

  final List<MovementWithProduct> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warehouse_outlined, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            const Text('No stock movements yet'),
            const SizedBox(height: 4),
            Text(
              'Record opening stock or add stock to build the ledger.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.outline),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: items.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) return const _LedgerHeader();
        final item = items[index - 1];
        return _MovementRow(item: item);
      },
    );
  }
}

class _LedgerHeader extends StatelessWidget {
  const _LedgerHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.outline,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Product', style: style)),
          Expanded(flex: 2, child: Text('Type', style: style)),
          SizedBox(
            width: 76,
            child: Text('Qty', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 28),
          SizedBox(
            width: 140,
            child: Text('Date', style: style),
          ),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: Text('Reason', style: style)),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.item});

  final MovementWithProduct item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final movement = item.movement;
    final product = item.product;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: movement.movementType
                      .color(context)
                      .withValues(alpha: 0.12),
                  child: Icon(
                    movement.movementType.icon,
                    size: 16,
                    color: movement.movementType.color(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    product.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          Expanded(flex: 2, child: Text(movement.movementType.label)),
          SizedBox(
            width: 76,
            child: Text(
              signedQuantity(movement.quantity),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: quantityColor(context, movement.quantity),
              ),
            ),
          ),
          const SizedBox(width: 28),
          SizedBox(
            width: 140,
            child: Text(
              _formatDate(movement.createdAt),
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.85),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Text(
              movement.reason ?? '—',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

/// Dialog for recording a manual stock movement against a chosen product.
Future<String?> showStockActionDialog({
  required BuildContext context,
  required WidgetRef ref,
  required ManualMovementAction action,
}) {
  final products =
      ref.read(productsProvider('')).value ?? const <ProductWithStock>[];
  final repository = ref.read(inventoryRepositoryProvider);

  return showDialog<String>(
    context: context,
    builder: (context) => _StockActionDialog(
      action: action,
      products: products,
      repository: repository,
    ),
  );
}

class _StockActionDialog extends ConsumerStatefulWidget {
  const _StockActionDialog({
    required this.action,
    required this.products,
    required this.repository,
  });

  final ManualMovementAction action;
  final List<ProductWithStock> products;
  final InventoryRepository repository;

  @override
  ConsumerState<_StockActionDialog> createState() => _StockActionDialogState();
}

class _StockActionDialogState extends ConsumerState<_StockActionDialog> {
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  String? _productId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.action == ManualMovementAction.adjust) {
      _reasonController.text = 'Physical stock count';
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  ({String title, String label, String helper}) get _copy =>
      switch (widget.action) {
        ManualMovementAction.add => (
          title: 'Add stock',
          label: 'Units received',
          helper: 'Records a PURCHASE movement (+quantity)',
        ),
        ManualMovementAction.damage => (
          title: 'Damage / write-off',
          label: 'Units damaged',
          helper: 'Records a DAMAGE movement (−quantity)',
        ),
        ManualMovementAction.adjust => (
          title: 'Adjust to physical count',
          label: 'Physical count',
          helper: 'Records an ADJUSTMENT for the difference',
        ),
      };

  ProductWithStock? get _selected {
    for (final item in widget.products) {
      if (item.product.id == _productId) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy;

    return AlertDialog(
      title: Text(copy.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Product *',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _productId,
                    isExpanded: true,
                    isDense: true,
                    hint: const Text('Select a product'),
                    items: [
                      for (final item in widget.products)
                        DropdownMenuItem<String?>(
                          value: item.product.id,
                          child: Text(
                            '${item.product.name}  '
                            '(stock: ${item.stock.toStringAsFixed(0)})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _productId = value),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _quantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '${copy.label} *',
                  helperText: copy.helper,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (widget.action != ManualMovementAction.add) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason *',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Recording…' : 'Record movement'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null) {
      setState(() => _error = 'Select a product.');
      return;
    }
    final quantity = double.tryParse(
      _quantityController.text.replaceAll(',', '.'),
    );
    final reason = _reasonController.text.trim();

    final MovementType type;
    final double signed;
    switch (widget.action) {
      case ManualMovementAction.add:
        if (quantity == null || quantity <= 0) {
          setState(() => _error = 'Enter the number of units received.');
          return;
        }
        type = MovementType.purchase;
        signed = quantity;
      case ManualMovementAction.damage:
        if (quantity == null || quantity <= 0) {
          setState(() => _error = 'Enter the number of damaged units.');
          return;
        }
        if (reason.isEmpty) {
          setState(() => _error = 'A reason is required for damage.');
          return;
        }
        type = MovementType.damage;
        signed = -quantity;
      case ManualMovementAction.adjust:
        if (quantity == null || quantity < 0) {
          setState(() => _error = 'Enter the physical count.');
          return;
        }
        if (reason.isEmpty) {
          setState(() => _error = 'A reason is required for adjustments.');
          return;
        }
        final difference = quantity - selected.stock;
        if (difference == 0) {
          setState(
            () => _error =
                'System stock already matches the physical count (${selected.stock.toStringAsFixed(0)}).',
          );
          return;
        }
        type = MovementType.adjustment;
        signed = difference;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.recordMovement(
        productId: selected.product.id,
        type: type,
        quantity: signed,
        reason: widget.action == ManualMovementAction.add && reason.isEmpty
            ? null
            : reason,
        userId: ref.read(currentUserProvider)?.id,
      );
      final verb = switch (widget.action) {
        ManualMovementAction.add => 'Added',
        ManualMovementAction.damage => 'Recorded damage on',
        ManualMovementAction.adjust => 'Adjusted',
      };
      if (mounted) {
        Navigator.of(context).pop(
          '$verb ${selected.product.name} '
          '(${signedQuantity(signed)} units)',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
