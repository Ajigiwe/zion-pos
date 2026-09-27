import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/settings/presentation/receipt_settings_providers.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';
import 'package:instrument_pos/features/sales/data/sales_repository.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';
import 'package:instrument_pos/features/sales/presentation/receipt_print_service.dart';
import 'package:instrument_pos/features/sales/presentation/receipt_view.dart';
import 'package:instrument_pos/features/sales/presentation/sales_providers.dart';
import 'package:instrument_pos/features/sales/presentation/barcode_scanner_listener.dart';
import 'package:instrument_pos/features/sales/presentation/barcode_scan_dialog.dart';

enum _SalesMode { register, history }

class SalesPage extends ConsumerStatefulWidget {
  const SalesPage({super.key});

  @override
  ConsumerState<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends ConsumerState<SalesPage> {
  final _searchController = TextEditingController();
  final _discountController = TextEditingController();
  final _paymentController = TextEditingController();
  final _paymentRefController = TextEditingController();
  final _searchFocus = FocusNode();
  final List<CartLine> _cart = [];
  final List<PaymentDraft> _payments = [];
  PaymentMethod _method = PaymentMethod.cash;
  _SalesMode _mode = _SalesMode.register;
  String _search = '';
  String? _selectedCategoryId;
  bool _saving = false;

  @override
  void dispose() {
    _searchController.dispose();
    _discountController.dispose();
    _paymentController.dispose();
    _paymentRefController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Enter on the search field rings the product up directly: a barcode
  /// scanner "types" the code and presses Enter, so the exact barcode/SKU/
  /// name match is added to the cart without a tap. A single partial match
  /// (one search result) is also accepted; ambiguous or unknown input stays
  /// in the list for the cashier to pick.
  Future<void> _handleSearchSubmit(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;
    var matches = await ref.read(productsRepositoryProvider).findByExact(query);
    if (matches.isEmpty) {
      final filtered =
          ref.read(productsProvider(query)).value ?? const <ProductWithStock>[];
      matches = filtered.length == 1 ? filtered : const [];
    }
    if (!mounted) return;
    if (matches.isEmpty) {
      _snack('No product matches “$query” — check the name or barcode.');
      return;
    }
    if (matches.length > 1) {
      _snack('${matches.length} products match “$query” — pick from the list.');
      return;
    }
    _addToCart(matches.single);
    _searchController.clear();
    setState(() => _search = '');
    // Keep the field ready for the next scan/keystroke.
    _searchFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return BarcodeScannerListener(
      onBarcodeScanned: (scannedCode) => _handleSearchSubmit(scannedCode),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Sales',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              SegmentedButton<_SalesMode>(
                segments: const [
                  ButtonSegment(
                    value: _SalesMode.register,
                    label: Text('New sale'),
                    icon: Icon(Icons.point_of_sale),
                  ),
                  ButtonSegment(
                    value: _SalesMode.history,
                    label: Text('History'),
                    icon: Icon(Icons.history),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) =>
                    setState(() => _mode = selection.first),
              ),
            ],
          ),
        ),
        Expanded(
          child: _mode == _SalesMode.register
              ? _buildRegister()
              : const _HistoryView(),
        ),
      ],
    ),
  );
}

  // ---------------------------------------------------------------- Register

  Widget _buildRegister() {
    final productsAsync = ref.watch(productsProvider(_search));
    final allProducts =
        (productsAsync.value ?? const <ProductWithStock>[])
            .where((p) => p.product.isActive)
            .toList();
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final products = _selectedCategoryId == null
        ? allProducts
        : allProducts
            .where((p) => p.product.categoryId == _selectedCategoryId)
            .toList();
    final totals = _currentTotals();

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: (value) => setState(() => _search = value.trim()),
                  onSubmitted: _handleSearchSubmit,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
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
                          tooltip: 'Scan Barcode',
                          onPressed: () {
                            BarcodeScanDialog.showForSales(
                              context,
                              onProductSelected: (product) {
                                _addToCart(product);
                              },
                            );
                          },
                        ),
                      ],
                    ),
                    hintText: 'Search product or scan barcode — press Enter to ring up',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              if (categories.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            avatar: const Icon(Icons.apps, size: 16),
                            label: const Text('All Products'),
                            selected: _selectedCategoryId == null,
                            onSelected: (_) =>
                                setState(() => _selectedCategoryId = null),
                          ),
                        ),
                        for (final cat in categories)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(cat.name),
                              selected: _selectedCategoryId == cat.id,
                              onSelected: (selected) => setState(() {
                                _selectedCategoryId = selected ? cat.id : null;
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: productsAsync.when(
                  loading: () => const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Connecting to Host Database…', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                  error: (err, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.signal_wifi_off_rounded, size: 48, color: Colors.orange),
                          const SizedBox(height: 12),
                          const Text(
                            'Connection to Host Server Lost',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Could not fetch product catalog: $err\nEnsure Host PC is powered on and connected to the shared network.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => ref.invalidate(productsProvider(_search)),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry Connection'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  data: (_) => products.isEmpty
                      ? const Center(child: Text('No products match.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: products.length,
                          itemBuilder: (context, index) =>
                              _buildProductTile(products[index]),
                        ),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 390,
          child: _CartPanel(
            cart: _cart,
            payments: _payments,
            method: _method,
            totals: totals,
            saving: _saving,
            discountController: _discountController,
            paymentController: _paymentController,
            paymentRefController: _paymentRefController,
            onMethodChanged: (m) => setState(() => _method = m),
            onDiscountChanged: () => setState(() {}),
            onIncrement: _increment,
            onDecrement: _decrement,
            onRemove: _removeLine,
            onAddPayment: _addPayment,
            onRemovePayment: _removePayment,
            onComplete: _completeSale,
            onSetCashAmount: (amount) {
              setState(() {
                _paymentController.text = amount.toStringAsFixed(2);
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProductTile(ProductWithStock item) {
    final product = item.product;
    final inStock = item.stock > 0;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () => _addToCart(item),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            product.trackingType == ProductTrackingType.serialized
                ? Icons.confirmation_number_outlined
                : Icons.inventory_2_outlined,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            size: 20,
          ),
        ),
        title: Text(
          product.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Row(
          children: [
            Text('${product.sku}  · '),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: inStock
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Stock: ${item.stock.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: inStock
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFC62828),
                ),
              ),
            ),
          ],
        ),
        trailing: Text(
          formatMoney(product.sellingPrice),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  void _addToCart(ProductWithStock item) {
    final existing = _cart
        .where((l) => l.productId == item.product.id)
        .firstOrNull;
    final currentQty = existing?.quantity ?? 0;
    if (currentQty + 1 > item.stock) {
      _snack(
        'Only ${item.stock.toStringAsFixed(0)} in stock for ${item.product.name}.',
      );
      return;
    }
    setState(() {
      if (existing != null) {
        existing.quantity += 1;
      } else {
        _cart.add(
          CartLine(
            productId: item.product.id,
            name: item.product.name,
            quantity: 1,
            unitPrice: item.product.sellingPrice,
            taxRate: item.product.taxRate,
          ),
        );
      }
      if (_payments.isEmpty) _paymentController.text = '';
    });
  }

  void _increment(CartLine line) {
    final product = ref
        .read(productsProvider(''))
        .value
        ?.where((p) => p.product.id == line.productId)
        .firstOrNull;
    if (product != null && line.quantity + 1 > product.stock) {
      _snack('Only ${product.stock.toStringAsFixed(0)} in stock.');
      return;
    }
    setState(() => line.quantity += 1);
  }

  void _decrement(CartLine line) {
    setState(() {
      if (line.quantity <= 1) {
        _cart.remove(line);
      } else {
        line.quantity -= 1;
      }
    });
  }

  void _removeLine(CartLine line) => setState(() => _cart.remove(line));

  SaleTotals _currentTotals() {
    final discount =
        double.tryParse(_discountController.text.replaceAll(',', '.')) ?? 0;
    return computeSaleTotals(
      lines: [
        for (final line in _cart)
          (gross: line.unitPrice * line.quantity, taxRate: line.taxRate),
      ],
      discount: discount,
    );
  }

  double get _paid => _payments.fold<double>(0, (sum, p) => sum + p.amount);

  void _addPayment() {
    final remaining = _currentTotals().total - _paid;
    final amount =
        double.tryParse(_paymentController.text.replaceAll(',', '.')) ??
        remaining;
    if (amount <= 0) {
      _snack('Enter a positive payment amount.');
      return;
    }
    if (_method != PaymentMethod.cash && amount > remaining + 0.005) {
      _snack(
        '${_method.label} overpayment is not allowed — use cash for change.',
      );
      return;
    }
    // Mobile money payments may carry the payer's number / transaction ID,
    // which is printed on the receipt.
    final reference = _method == PaymentMethod.mobileMoney
        ? _paymentRefController.text.trim()
        : '';
    setState(() {
      _payments.add(
        PaymentDraft(
          method: _method,
          amount: amount,
          reference: reference.isEmpty ? null : reference,
        ),
      );
      _paymentController.clear();
      _paymentRefController.clear();
    });
  }

  void _removePayment(int index) => setState(() => _payments.removeAt(index));
  Future<void> _completeSale() async {
    final cashier = ref.read(currentUserProvider);
    if (cashier == null) {
      _snack('Sign in to complete sales.');
      return;
    }
    final totals = _currentTotals();
    final snapshotLines = [
      for (final line in _cart)
        (name: line.name, quantity: line.quantity, unitPrice: line.unitPrice),
    ];
    setState(() => _saving = true);
    try {
      final completed = await ref
          .read(salesRepositoryProvider)
          .completeSale(
            SaleRequest(
              lines: [
                for (final line in _cart)
                  (productId: line.productId, quantity: line.quantity),
              ],
              payments: List.of(_payments),
              discount: totals.discount,
              cashierId: cashier.id,
            ),
          );
      final paidSnapshot = List.of(_payments);
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _payments.clear();
        _discountController.clear();
      });
      final receipt = ReceiptContent(
        store: ref.read(storeInfoControllerProvider),
        receiptNumber: completed.receiptNumber,
        createdAt: DateTime.now(),
        totals: totals,
        lines: snapshotLines,
        payments: paidSnapshot,
        change: completed.change,
        cashierName: cashier.displayName,
        customization: ref.read(receiptCustomizationControllerProvider),
      );
      unawaited(printReceipt(ref, content: receipt));
      final changeText = completed.change > 0
          ? ' · Change due: ${formatMoney(completed.change)}'
          : '';
      _snack(
        'Sale ${completed.receiptNumber} complete (${formatMoney(completed.total)})$changeText',
      );
    } on StockShortageException catch (e) {
      _snack(e.message);
    } on PaymentException catch (e) {
      _snack(e.message);
    } catch (e) {
      // Anything else (a UNIQUE receipt clash, a database error) must never
      // fail silently: the cashier would tap "Complete sale" and see nothing.
      debugPrint('[SalesPage] complete sale failed: $e');
      _snack('Could not complete the sale: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.cart,
    required this.payments,
    required this.method,
    required this.totals,
    required this.saving,
    required this.discountController,
    required this.paymentController,
    required this.paymentRefController,
    required this.onMethodChanged,
    required this.onDiscountChanged,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onAddPayment,
    required this.onRemovePayment,
    required this.onComplete,
    required this.onSetCashAmount,
  });

  final List<CartLine> cart;
  final List<PaymentDraft> payments;
  final PaymentMethod method;
  final SaleTotals totals;
  final bool saving;
  final TextEditingController discountController;
  final TextEditingController paymentController;
  final TextEditingController paymentRefController;
  final ValueChanged<PaymentMethod> onMethodChanged;
  final VoidCallback onDiscountChanged;
  final ValueChanged<CartLine> onIncrement;
  final ValueChanged<CartLine> onDecrement;
  final ValueChanged<CartLine> onRemove;
  final VoidCallback onAddPayment;
  final ValueChanged<int> onRemovePayment;
  final VoidCallback onComplete;
  final ValueChanged<double> onSetCashAmount;

  double get _paid => payments.fold<double>(0, (sum, p) => sum + p.amount);
  double get _remaining => (totals.total - _paid).clamp(0, double.infinity);
  double get _change => _paid > totals.total ? _paid - totals.total : 0;
  bool get _covered => _remaining <= 0.005;

  List<double> _getQuickCashOptions(double remaining) {
    if (remaining <= 0) return const [];
    final options = <double>{};
    final notes = [10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0];
    for (final note in notes) {
      if (note >= remaining && options.length < 4) {
        options.add(note);
      }
    }
    if (options.isEmpty) {
      final ceil50 = (remaining / 50).ceil() * 50.0;
      final ceil100 = (remaining / 100).ceil() * 100.0;
      options.add(ceil50);
      if (ceil100 > ceil50) options.add(ceil100);
    }
    return options.toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quickCashList = _getQuickCashOptions(_remaining);

    return Column(
      children: [
        // Cart Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              const Icon(Icons.shopping_bag_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                'Current Sale',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${cart.length} item${cart.length == 1 ? '' : 's'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Cart Items List
        Expanded(
          child: cart.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_shopping_cart_outlined,
                          size: 48,
                          color: theme.colorScheme.outline.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Cart is empty.\nTap products to add them.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: cart.length,
                  itemBuilder: (context, index) => _CartLineTile(
                    line: cart[index],
                    onIncrement: onIncrement,
                    onDecrement: onDecrement,
                    onRemove: onRemove,
                  ),
                ),
        ),
        const Divider(height: 1),

        // Subtotals & Discount
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Text('Subtotal', style: theme.textTheme.bodySmall),
                  const Spacer(),
                  Text(
                    formatMoney(totals.grossSubtotal),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('Discount', style: theme.textTheme.bodySmall),
                  const Spacer(),
                  SizedBox(
                    width: 110,
                    height: 32,
                    child: TextField(
                      controller: discountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(),
                        suffixText: 'GHS',
                        suffixStyle: TextStyle(fontSize: 11),
                      ),
                      onChanged: (_) => onDiscountChanged(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    'VAT (included)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatMoney(totals.taxIncluded),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Hero Grand Total
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL DUE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            '${cart.fold<double>(0, (sum, l) => sum + l.quantity).toStringAsFixed(0)} units',
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatMoney(totals.total),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Payments Section
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (payments.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final p in payments)
                      InputChip(
                        avatar: Icon(
                          p.method == PaymentMethod.cash
                              ? Icons.payments_outlined
                              : p.method == PaymentMethod.card
                                  ? Icons.credit_card_outlined
                                  : Icons.phone_android_outlined,
                          size: 16,
                        ),
                        label: Text(
                          '${p.method.label} ${formatMoney(p.amount)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onDeleted: () => onRemovePayment(payments.indexOf(p)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
              ],

              // Balance or Change
              if (!_covered)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Remaining Balance',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(_remaining),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),

              if (_change > 0)
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFA5D6A7)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.change_circle_outlined,
                        color: Color(0xFF2E7D32),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'CHANGE DUE',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                            letterSpacing: 0.8,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                      Text(
                        formatMoney(_change),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                    ],
                  ),
                ),

              if (!_covered) ...[
                const SizedBox(height: 8),
                // Payment Method Chips
                Wrap(
                  spacing: 6,
                  children: [
                    for (final m in kAcceptedPaymentMethods)
                      ChoiceChip(
                        label: Text(m.label, style: const TextStyle(fontSize: 12)),
                        selected: method == m,
                        onSelected: (_) => onMethodChanged(m),
                      ),
                  ],
                ),

                // Quick-cash shortcuts for Cash
                if (method == PaymentMethod.cash && quickCashList.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.bolt, size: 14),
                        label: Text('Exact (${formatMoney(_remaining)})'),
                        labelStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        onPressed: () => onSetCashAmount(_remaining),
                      ),
                      for (final cashOption in quickCashList)
                        ActionChip(
                          label: Text('Pay ${formatMoney(cashOption)}'),
                          labelStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          onPressed: () => onSetCashAmount(cashOption),
                        ),
                    ],
                  ),
                ],

                if (method == PaymentMethod.mobileMoney) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: paymentRefController,
                    decoration: const InputDecoration(
                      labelText: 'MoMo reference (optional)',
                      hintText: 'Payer number or transaction ID',
                      prefixIcon: Icon(Icons.tag, size: 20),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: paymentController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount received',
                          border: OutlineInputBorder(),
                          isDense: true,
                          suffixText: 'GHS',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: onAddPayment,
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton.icon(
                  onPressed: _covered && cart.isNotEmpty && !saving
                      ? onComplete
                      : null,
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text(
                    'Complete sale',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.line,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  final CartLine line;
  final ValueChanged<CartLine> onIncrement;
  final ValueChanged<CartLine> onDecrement;
  final ValueChanged<CartLine> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${formatMoney(line.unitPrice * line.quantity)}  (${line.quantity.toStringAsFixed(0)} × ${formatMoney(line.unitPrice)})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Quantity Stepper
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  icon: const Icon(Icons.remove),
                  onPressed: () => onDecrement(line),
                ),
                SizedBox(
                  width: 20,
                  child: Text(
                    line.quantity.toStringAsFixed(0),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  icon: const Icon(Icons.add),
                  onPressed: () => onIncrement(line),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: theme.colorScheme.error.withValues(alpha: 0.8),
            icon: const Icon(Icons.close),
            onPressed: () => onRemove(line),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- History

class _HistoryView extends ConsumerWidget {
  const _HistoryView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(recentSalesProvider);
    return sales.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('No sales yet.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final sale = items[index];
            return ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(
                '${sale.receiptNumber}  ·  ${formatMoney(sale.total)}',
              ),
              subtitle: Text(_formatDate(sale.createdAt)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showSaleDetailDialog(context, ref, sale.id),
            );
          },
        );
      },
    );
  }

  static String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

Future<void> showSaleDetailDialog(
  BuildContext context,
  WidgetRef ref,
  String saleId,
) async {
  final detail = await ref.read(saleDetailProvider(saleId).future);
  if (!context.mounted) return;

  final totals = SaleTotals(
    grossSubtotal: detail.sale.subtotal,
    discount: detail.sale.discount,
    taxIncluded: detail.sale.tax,
    total: detail.sale.total,
  );
  final receipt = ReceiptContent(
    store: ref.read(storeInfoControllerProvider),
    receiptNumber: detail.sale.receiptNumber,
    createdAt: detail.sale.createdAt,
    totals: totals,
    lines: [
      for (final entry in detail.items)
        (
          name: entry.productName,
          quantity: entry.item.quantity,
          unitPrice: entry.item.unitPrice,
        ),
    ],
    payments: [
      for (final p in detail.payments)
        PaymentDraft(
          method: p.paymentMethod,
          amount: p.amount,
          reference: p.reference,
        ),
    ],
    change: _paid(detail.payments) - detail.sale.total,
    customization: ref.read(receiptCustomizationControllerProvider),
  );

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Sale ${detail.sale.receiptNumber}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in detail.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${entry.productName} × '
                          '${entry.item.quantity.toStringAsFixed(0)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(formatMoney(entry.item.subtotal)),
                    ],
                  ),
                ),
              const Divider(),
              Row(
                children: [
                  const Expanded(child: Text('Total')),
                  Text(
                    formatMoney(detail.sale.total),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              for (final p in detail.payments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${p.paymentMethod.label}: ${formatMoney(p.amount)}',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _showReceipt(
            context,
            receipt,
            onPrint: () => _printAndSnack(context, ref, receipt),
          ),
          child: const Text('View receipt'),
        ),
        OutlinedButton.icon(
          onPressed: () => _printAndSnack(context, ref, receipt),
          icon: const Icon(Icons.print_outlined),
          label: const Text('Print'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

double _paid(List<Payment> payments) =>
    payments.fold<double>(0, (sum, p) => sum + p.amount);

/// Shows the receipt (paper-look view), with a Print action when [onPrint] is
/// given.
void _showReceipt(
  BuildContext context,
  ReceiptContent content, {
  Future<void> Function()? onPrint,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Receipt'),
      content: SingleChildScrollView(child: ReceiptView(content: content)),
      actions: [
        if (onPrint != null)
          OutlinedButton.icon(
            onPressed: onPrint,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Prints a receipt through the native dialog and reports the outcome.
Future<void> _printAndSnack(
  BuildContext context,
  WidgetRef ref,
  ReceiptContent content,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final printed = await printReceipt(ref, content: content);
  if (!context.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          printed
              ? 'Receipt ${content.receiptNumber} sent to printer.'
              : 'Print cancelled.',
        ),
      ),
    );
}
