import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/domain/product.dart';
import 'package:instrument_pos/features/products/presentation/product_edit_page.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

enum ProductFilter { active, inactive, all }

class _ProductsPageState extends ConsumerState<ProductsPage> {
  final _searchController = TextEditingController();
  String _query = '';
  ProductFilter _filter = ProductFilter.active;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsStream = ref.watch(productsProvider(_query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value.trim()),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by name, SKU or barcode…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<ProductFilter>(
                segments: const [
                  ButtonSegment(
                    value: ProductFilter.active,
                    label: Text('Active'),
                    icon: Icon(Icons.check_circle_outline, size: 16),
                  ),
                  ButtonSegment(
                    value: ProductFilter.inactive,
                    label: Text('Hidden'),
                    icon: Icon(Icons.visibility_off_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: ProductFilter.all,
                    label: Text('All'),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (newSelection) {
                  setState(() => _filter = newSelection.first);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: productsStream.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(child: Text('Error: $error')),
            data: (allRawItems) {
              final items = allRawItems.where((i) {
                if (_filter == ProductFilter.active) return i.product.isActive;
                if (_filter == ProductFilter.inactive) return !i.product.isActive;
                return true;
              }).toList();

              if (items.isEmpty) {
                return Center(
                  child: Text(
                    _filter == ProductFilter.inactive
                        ? 'No hidden/deactivated products.'
                        : 'No products yet. Add your first product.',
                  ),
                );
              }
              return Column(
                children: [
                  const _HeaderRow(),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _ProductRow(item: item);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.outline,
      fontWeight: FontWeight.w600,
    );

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('Product & SKU', style: style)),
          Expanded(flex: 2, child: Text('Type', style: style)),
          Expanded(
            flex: 2,
            child: Text('Stock', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Text('Price', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Text('Status', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 3,
            child: Text('Actions', style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _ProductRow extends ConsumerWidget {
  const _ProductRow({required this.item});

  final ProductWithStock item;

  void _showContextMenu(BuildContext context, WidgetRef ref, Offset position) async {
    final product = item.product;
    final repo = ref.read(productsRepositoryProvider);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: 'view',
          child: Row(
            children: [
              Icon(Icons.visibility_outlined, size: 20),
              SizedBox(width: 8),
              Text('View Details'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20),
              SizedBox(width: 8),
              Text('Edit Product'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'toggle_active',
          child: Row(
            children: [
              Icon(
                product.isActive ? Icons.power_settings_new : Icons.check_circle_outline,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(product.isActive ? 'Deactivate' : 'Reactivate'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text('Delete Product', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );

    if (!context.mounted) return;

    if (selected == 'view') {
      _showProductDetail(context, ref, item);
    } else if (selected == 'edit') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProductEditPage(productId: product.id),
        ),
      );
    } else if (selected == 'toggle_active') {
      await repo.setActive(product.id, active: !product.isActive);
    } else if (selected == 'delete') {
      _confirmDeleteProduct(context, ref, product);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = item.product;
    final theme = Theme.of(context);
    final lowStock = product.reorderLevel > 0 && item.stock <= product.reorderLevel;

    return GestureDetector(
      onSecondaryTapDown: (details) => _showContextMenu(context, ref, details.globalPosition),
      child: InkWell(
        onTap: () => _showProductDetail(context, ref, item),
        onLongPress: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductEditPage(productId: product.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              // Product Name & SKU
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Icon(
                      product.trackingType == ProductTrackingType.serialized
                          ? Icons.confirmation_number_outlined
                          : Icons.inventory_2_outlined,
                      color: product.isActive ? theme.colorScheme.primary : theme.disabledColor,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: product.isActive ? null : theme.disabledColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'SKU: ${product.sku}${product.barcode != null ? ' • ${product.barcode}' : ''}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Tracking Type
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      product.trackingType == ProductTrackingType.serialized ? 'Serialized' : 'Quantity',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ),
              ),

              // Stock
              Expanded(
                flex: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (lowStock) ...[
                      Tooltip(
                        message: 'Low stock warning (Limit: ${product.reorderLevel.toStringAsFixed(0)})',
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: theme.colorScheme.error,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      item.stock.toStringAsFixed(0),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: lowStock ? theme.colorScheme.error : null,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Price
              Expanded(
                flex: 2,
                child: Text(
                  'GHS ${product.sellingPrice.toStringAsFixed(0)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),

              const SizedBox(width: 16),

              // Status
              Expanded(
                flex: 2,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: product.isActive
                          ? Colors.green.withOpacity(0.12)
                          : theme.disabledColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      product.isActive ? 'Active' : 'Inactive',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: product.isActive ? Colors.green.shade800 : theme.disabledColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

              // Action Buttons
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.visibility_outlined, size: 20),
                      tooltip: 'View details',
                      onPressed: () => _showProductDetail(context, ref, item),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Edit product',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductEditPage(productId: product.id),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      tooltip: 'Delete product',
                      onPressed: () => _confirmDeleteProduct(context, ref, product),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showProductDetail(BuildContext context, WidgetRef ref, ProductWithStock item) {
  final product = item.product;
  final theme = Theme.of(context);
  final margin = product.sellingPrice > 0
      ? ((product.sellingPrice - product.costPrice) / product.sellingPrice * 100)
      : 0.0;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(
            product.trackingType == ProductTrackingType.serialized
                ? Icons.confirmation_number
                : Icons.inventory_2,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: theme.textTheme.titleLarge),
                Text('SKU: ${product.sku}', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: product.isActive
                  ? Colors.green.withOpacity(0.15)
                  : Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              product.isActive ? 'Active' : 'Inactive',
              style: TextStyle(
                color: product.isActive ? Colors.green.shade800 : Colors.grey.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(),
              const SizedBox(height: 8),
              _DetailRow(label: 'Selling Price', value: 'GHS ${product.sellingPrice.toStringAsFixed(2)}'),
              _DetailRow(label: 'Cost Price', value: 'GHS ${product.costPrice.toStringAsFixed(2)}'),
              _DetailRow(label: 'Estimated Margin', value: '${margin.toStringAsFixed(1)}%'),
              _DetailRow(label: 'Stock Level', value: '${item.stock.toStringAsFixed(0)} units'),
              _DetailRow(label: 'Reorder Level', value: '${product.reorderLevel.toStringAsFixed(0)} units'),
              _DetailRow(label: 'Barcode', value: product.barcode ?? 'None'),
              _DetailRow(label: 'Tax Rate', value: '${product.taxRate.toStringAsFixed(1)}%'),
              _DetailRow(
                label: 'Tracking Type',
                value: product.trackingType == ProductTrackingType.serialized
                    ? 'Serialized (Unique Serial #)'
                    : 'Quantity (Standard Batch)',
              ),
              if (product.description != null && product.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Description', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(product.description!, style: theme.textTheme.bodyMedium),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Navigator.of(ctx).pop();
            _confirmDeleteProduct(context, ref, product);
          },
          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
          label: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(ctx).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProductEditPage(productId: product.id),
              ),
            );
          },
          icon: const Icon(Icons.edit, size: 18),
          label: const Text('Edit Product'),
        ),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmDeleteProduct(BuildContext context, WidgetRef ref, Product product) async {
  final repo = ref.read(productsRepositoryProvider);
  final canHardDelete = await repo.canHardDelete(product.id);

  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        canHardDelete ? 'Delete ${product.name}?' : 'Deactivate ${product.name}?',
      ),
      content: Text(
        canHardDelete
            ? 'This product has no sales or stock history and will be permanently deleted.'
            : 'This product is referenced in historical sales or stock records. To keep past receipts and audit logs accurate, it will be deactivated (hidden from POS sales).',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            canHardDelete ? 'Delete permanently' : 'Deactivate',
          ),
        ),
      ],
    ),
  );

  if (confirmed == true && context.mounted) {
    final hardDeleted = await repo.deleteProduct(product.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            hardDeleted
                ? 'Product permanently deleted.'
                : 'Product deactivated (historical records preserved).',
          ),
        ),
      );
  }
}

