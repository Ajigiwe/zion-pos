import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/products/domain/product.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';
import 'package:instrument_pos/features/sales/presentation/barcode_scan_dialog.dart';

class ProductEditPage extends ConsumerStatefulWidget {
  const ProductEditPage({super.key, this.productId});

  /// When null, the form creates a new product.
  final String? productId;

  @override
  ConsumerState<ProductEditPage> createState() => _ProductEditPageState();
}

class _ProductEditPageState extends ConsumerState<ProductEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _costController = TextEditingController();
  final _priceController = TextEditingController();
  final _taxController = TextEditingController();
  final _reorderController = TextEditingController();

  String? _categoryId;
  String? _brandId;
  ProductTrackingType _trackingType = ProductTrackingType.quantity;
  bool _isActive = true;
  bool _saving = false;
  bool _loaded = false;

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _descriptionController.dispose();
    _costController.dispose();
    _priceController.dispose();
    _taxController.dispose();
    _reorderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.productId == null
        ? null
        : ref.watch(productProvider(widget.productId!)).value;

    _hydrate(product);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.productId == null ? 'New Product' : 'Edit Product'),
        actions: [
          if (widget.productId != null && product != null)
            PopupMenuButton<String>(
              onSelected: (value) async {
                final repo = ref.read(productsRepositoryProvider);
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);

                if (value == 'deactivate') {
                  await repo.setActive(product.id, active: !product.isActive);
                  if (mounted) navigator.pop();
                } else if (value == 'delete') {
                  final canHardDelete = await repo.canHardDelete(product.id);
                  if (!context.mounted) return;
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(
                        canHardDelete
                            ? 'Delete ${product.name}'
                            : 'Deactivate ${product.name}',
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
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: Text(
                            canHardDelete
                                ? 'Delete permanently'
                                : 'Deactivate',
                          ),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true && mounted) {
                    final hardDeleted = await repo.deleteProduct(product.id);
                    messenger
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
                    navigator.pop();
                  }
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'deactivate',
                  child: Text(
                    product.isActive ? 'Deactivate product' : 'Reactivate product',
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('Delete product', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: product == null && widget.productId != null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _nameField(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _skuField()),
                          const SizedBox(width: 12),
                          Expanded(child: _barcodeField()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _categoryDropdown()),
                          const SizedBox(width: 12),
                          Expanded(child: _brandDropdown()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _descriptionField(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _moneyField(
                              _costController,
                              'Cost price (GHS)',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _moneyField(
                              _priceController,
                              'Selling price (GHS)',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _moneyField(
                              _taxController,
                              'Tax rate (%)',
                              suffix: '%',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _moneyField(
                              _reorderController,
                              'Reorder level',
                              suffix: '',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _trackingTypeField(),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Active'),
                        subtitle: const Text(
                          'Inactive products are hidden from the catalog',
                        ),
                        value: _isActive,
                        onChanged: (value) => setState(() => _isActive = value),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save),
                        label: Text(
                          widget.productId == null
                              ? 'Create Product'
                              : 'Save Changes',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  void _hydrate(Product? product) {
    if (product == null || _loaded) return;
    _loaded = true;
    _nameController.text = product.name;
    _skuController.text = product.sku;
    _barcodeController.text = product.barcode ?? '';
    _descriptionController.text = product.description ?? '';
    _costController.text = _fmt(product.costPrice);
    _priceController.text = _fmt(product.sellingPrice);
    _taxController.text = _fmt(product.taxRate);
    _reorderController.text = _fmt(product.reorderLevel);
    _categoryId = product.categoryId;
    _brandId = product.brandId;
    _trackingType = product.trackingType;
    _isActive = product.isActive;
  }

  static String _fmt(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  Widget _nameField() => TextFormField(
    controller: _nameController,
    decoration: const InputDecoration(
      labelText: 'Product name *',
      border: OutlineInputBorder(),
    ),
    validator: (v) =>
        (v == null || v.trim().isEmpty) ? 'Name is required' : null,
  );

  Widget _skuField() => TextFormField(
    controller: _skuController,
    decoration: const InputDecoration(
      labelText: 'SKU',
      hintText: 'e.g. YAM-PSR-E473',
      border: OutlineInputBorder(),
    ),
  );

  void _generateUniqueBarcode() {
    // Generate a 12-digit base with retail in-store prefix "20"
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final base = '20${timestamp.substring(timestamp.length - 10)}';
    // Calculate EAN-13 check digit
    int sum = 0;
    for (int i = 0; i < base.length; i++) {
      final digit = int.parse(base[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }
    final checkDigit = (10 - (sum % 10)) % 10;
    final barcode = '$base$checkDigit';
    setState(() {
      _barcodeController.text = barcode;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Generated unique barcode: $barcode'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _barcodeField() => TextFormField(
    controller: _barcodeController,
    decoration: InputDecoration(
      labelText: 'Barcode',
      hintText: 'e.g. 2001234567890',
      border: const OutlineInputBorder(),
      suffixIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
            tooltip: 'Scan Barcode',
            onPressed: () async {
              final code = await BarcodeScanDialog.showForBarcode(context);
              if (code != null && code.isNotEmpty) {
                setState(() => _barcodeController.text = code);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded, size: 20),
            tooltip: 'Auto-generate Barcode',
            onPressed: _generateUniqueBarcode,
          ),
        ],
      ),
    ),
  );

  Widget _descriptionField() => TextFormField(
    controller: _descriptionController,
    maxLines: 3,
    decoration: const InputDecoration(
      labelText: 'Description',
      border: OutlineInputBorder(),
    ),
  );

  Widget _moneyField(
    TextEditingController controller,
    String label, {
    String suffix = '',
  }) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      suffixText: suffix.isEmpty ? null : suffix,
      border: const OutlineInputBorder(),
    ),
    validator: (v) {
      if (v == null || v.isEmpty) return null;
      final value = double.tryParse(v.replaceAll(',', '.'));
      return value == null || value < 0 ? 'Enter a valid number' : null;
    },
  );

  Widget _categoryDropdown() => DropdownButtonFormField<String?>(
    initialValue: _categoryId,
    decoration: const InputDecoration(
      labelText: 'Category',
      border: OutlineInputBorder(),
    ),
    items: [
      const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
      ...(ref.watch(categoriesProvider).value ?? const <Category>[]).map(
        (c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
      ),
    ],
    onChanged: (value) => setState(() => _categoryId = value),
  );

  Widget _brandDropdown() => DropdownButtonFormField<String?>(
    initialValue: _brandId,
    decoration: const InputDecoration(
      labelText: 'Brand',
      border: OutlineInputBorder(),
    ),
    items: [
      const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
      ...(ref.watch(brandsProvider).value ?? const <Brand>[]).map(
        (b) => DropdownMenuItem<String?>(value: b.id, child: Text(b.name)),
      ),
    ],
    onChanged: (value) => setState(() => _brandId = value),
  );

  Widget _trackingTypeField() => DropdownButtonFormField<ProductTrackingType>(
    initialValue: _trackingType,
    decoration: const InputDecoration(
      labelText: 'Tracking type',
      border: OutlineInputBorder(),
    ),
    items: const [
      DropdownMenuItem(
        value: ProductTrackingType.quantity,
        child: Text('Quantity'),
      ),
      DropdownMenuItem(
        value: ProductTrackingType.serialized,
        child: Text('Serialized (per instrument)'),
      ),
    ],
    onChanged: (value) => setState(() => _trackingType = value!),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(productsRepositoryProvider);
      await repo.upsert(
        ProductDraft(
          id: widget.productId,
          name: _nameController.text.trim(),
          sku: _skuController.text.trim().isEmpty
              ? null
              : _skuController.text.trim(),
          barcode: _barcodeController.text.trim().isEmpty
              ? null
              : _barcodeController.text.trim(),
          categoryId: _categoryId,
          brandId: _brandId,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          costPrice: _parse(_costController.text),
          sellingPrice: _parse(_priceController.text),
          taxRate: _parse(_taxController.text),
          reorderLevel: _parse(_reorderController.text),
          trackingType: _trackingType,
          isActive: _isActive,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      setState(() => _saving = false);
    }
  }

  double _parse(String text) {
    final value = double.tryParse(text.replaceAll(',', '.'));
    return value ?? 0;
  }
}
