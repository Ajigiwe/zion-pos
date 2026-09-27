import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/domain/product.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';
import 'package:instrument_pos/features/refunds/domain/refund_models.dart';
import 'package:instrument_pos/features/refunds/presentation/refunds_providers.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';
import 'package:instrument_pos/features/sales/presentation/sales_providers.dart';

enum RefundFlowMode { refund, exchange }

class RefundFlowPage extends ConsumerStatefulWidget {
  const RefundFlowPage({super.key, required this.saleId, required this.mode});

  final String saleId;
  final RefundFlowMode mode;

  @override
  ConsumerState<RefundFlowPage> createState() => _RefundFlowPageState();
}

class _RefundFlowPageState extends ConsumerState<RefundFlowPage> {
  final Map<String, double> _returnQuantities = {};
  final Map<String, double> _replacementQuantities = {};
  final Map<String, Product> _replacementProducts = {};
  final _reasonController = TextEditingController();
  final _searchController = TextEditingController();
  final _balanceController = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  String _search = '';
  bool _saving = false;
  double? _lastBalanceDue;

  @override
  void dispose() {
    _reasonController.dispose();
    _searchController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  bool get _isExchange => widget.mode == RefundFlowMode.exchange;

  void _syncBalanceDue(double balanceDue) {
    if (_lastBalanceDue != balanceDue) {
      _lastBalanceDue = balanceDue;
      if (balanceDue > 0) {
        _balanceController.text = balanceDue.toStringAsFixed(2);
      } else {
        _balanceController.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(saleDetailProvider(widget.saleId));
    final remainingAsync = ref.watch(
      refundableQuantitiesProvider(widget.saleId),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isExchange ? 'Exchange items' : 'Refund items'),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (detail) => remainingAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Error: $error')),
          data: (remaining) {
            final user = ref.watch(currentUserProvider);
            final returnCredit = _returnCredit(detail);
            final replacementTotal = _replacementTotal;
            final breakdown = computeExchangeBreakdown(
              returnCredit: returnCredit,
              replacementTotal: replacementTotal,
            );

            if (_isExchange) {
              _syncBalanceDue(breakdown.balanceDue);
            }

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Sale Header Card
                    Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.receipt_long_outlined, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sale ${detail.sale.receiptNumber}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    formatDateTime(detail.sale.createdAt),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Section 1: Return Items
                    Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '1. Select items being returned',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            for (final entry in detail.items)
                              _ReturnLineTile(
                                productName: entry.productName,
                                unitPrice: entry.item.unitPrice,
                                remaining: remaining[entry.item.id] ?? 0,
                                quantity: _returnQuantities[entry.item.id] ?? 0,
                                onChanged: (value) => setState(() {
                                  if (value <= 0) {
                                    _returnQuantities.remove(entry.item.id);
                                  } else {
                                    _returnQuantities[entry.item.id] = value;
                                  }
                                }),
                              ),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Return Credit:',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  formatMoney(returnCredit),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Section 2: Replacement Items (Exchange Mode Only)
                    if (_isExchange) ...[
                      Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '2. Select replacement product',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),

                              // Replacement Cart
                              if (_replacementQuantities.isNotEmpty) ...[
                                Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    children: [
                                      for (final entry
                                          in _replacementQuantities.entries)
                                        _ReplacementTile(
                                          name: _nameOf(entry.key),
                                          unitPrice: _priceOf(entry.key),
                                          quantity: entry.value,
                                          onChanged: (value) => setState(() {
                                            if (value <= 0) {
                                              _replacementQuantities
                                                  .remove(entry.key);
                                            } else {
                                              _replacementQuantities[
                                                  entry.key] = value;
                                            }
                                          }),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],

                              // Search Bar
                              TextField(
                                controller: _searchController,
                                onChanged: (value) =>
                                    setState(() => _search = value.trim()),
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: _search.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _search = '');
                                          },
                                        )
                                      : null,
                                  hintText: 'Type product name or SKU to add…',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Search Results (Only shown when searching)
                              if (_search.isNotEmpty) ...[
                                if (_catalog.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Center(
                                      child: Text(
                                        'No matching products found.',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                  )
                                else
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 240,
                                    ),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: _catalog.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final product = _catalog[index];
                                        final hasStock = product.stock > 0;
                                        return ListTile(
                                          dense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 4,
                                              ),
                                          title: Text(
                                            product.product.name,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: hasStock
                                                  ? null
                                                  : Colors.grey,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${formatMoney(product.product.sellingPrice)} · '
                                            '${hasStock ? "stock ${product.stock.toStringAsFixed(0)}" : "Out of stock"}',
                                            style: TextStyle(
                                              color: hasStock
                                                  ? null
                                                  : Colors.red.shade400,
                                            ),
                                          ),
                                          trailing: ElevatedButton.icon(
                                            icon: const Icon(
                                              Icons.add,
                                              size: 16,
                                            ),
                                            label: const Text('Add'),
                                            style: ElevatedButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            onPressed: hasStock
                                                ? () {
                                                    _addReplacement(product);
                                                    _searchController.clear();
                                                    setState(() => _search = '');
                                                  }
                                                : null,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                              ] else if (_replacementQuantities.isEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    'Use the search bar above to find and add replacement items.',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],

                    // Section 3: Settlement Card
                    Card(
                      margin: const EdgeInsets.only(bottom: 20),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isExchange
                                  ? '3. Exchange Settlement'
                                  : '2. Refund Settlement',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),

                            if (_isExchange) ...[
                              _buildExchangeSummary(breakdown),
                            ] else ...[
                              Text(
                                'Refund method',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                children: [
                                  for (final m in kAcceptedPaymentMethods)
                                    ChoiceChip(
                                      label: Text(m.label),
                                      selected: _method == m,
                                      onSelected: (_) =>
                                          setState(() => _method = m),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _reasonController,
                                decoration: const InputDecoration(
                                  labelText: 'Reason (optional)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // Action Button
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed:
                            _saving || user == null || !_canSubmit(detail)
                                ? null
                                : _commit,
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text(
                          _submitButtonLabel(detail, breakdown),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _submitButtonLabel(
    SaleDetail detail,
    ExchangeBreakdown breakdown,
  ) {
    if (!_isExchange) {
      return 'Refund ${formatMoney(_returnCredit(detail))}';
    }
    if (breakdown.balanceDue > 0) {
      return 'Complete Exchange (Pay ${formatMoney(breakdown.balanceDue)})';
    } else if (breakdown.cashBack > 0) {
      return 'Complete Exchange (Refund ${formatMoney(breakdown.cashBack)})';
    }
    return 'Complete Exchange';
  }

  Widget _buildExchangeSummary(ExchangeBreakdown breakdown) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Replacement Total:'),
            Text(
              formatMoney(breakdown.replacementTotal),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Return Credit:'),
            Text(
              '- ${formatMoney(breakdown.returnCredit)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const Divider(height: 20),

        if (breakdown.balanceDue > 0) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Customer pays difference:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                      ),
                    ),
                    Text(
                      formatMoney(breakdown.balanceDue),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Payment method:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final m in kAcceptedPaymentMethods)
                      ChoiceChip(
                        label: Text(m.label),
                        selected: _method == m,
                        onSelected: (_) => setState(() => _method = m),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _balanceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Balance payment amount',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ] else if (breakdown.cashBack > 0) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.payments_outlined,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Refund Cash Difference',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                      Text(
                        'Replacement is cheaper — return ${formatMoney(breakdown.cashBack)} in cash to customer.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else if (_replacementQuantities.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700),
                const SizedBox(width: 10),
                Text(
                  'Even Exchange — No additional payment required.',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<ProductWithStock> get _catalog {
    final all =
        ref.watch(productsProvider(_search)).value ??
        const <ProductWithStock>[];
    return all
        .where((p) => p.product.isActive && !_replacementQuantities.containsKey(p.product.id))
        .toList();
  }

  double _returnCredit(SaleDetail detail) {
    var credit = 0.0;
    for (final entry in detail.items) {
      final qty = _returnQuantities[entry.item.id] ?? 0;
      credit += entry.item.unitPrice * qty;
    }
    return credit;
  }

  double get _replacementTotal {
    var total = 0.0;
    for (final entry in _replacementQuantities.entries) {
      total += _priceOf(entry.key) * entry.value;
    }
    return total;
  }

  String _nameOf(String productId) =>
      _replacementProducts[productId]?.name ?? 'Product';

  double _priceOf(String productId) =>
      _replacementProducts[productId]?.sellingPrice ?? 0;

  void _addReplacement(ProductWithStock product) {
    if (product.stock < 1) {
      _snack('No stock for ${product.product.name}.');
      return;
    }
    setState(() {
      _replacementProducts[product.product.id] = product.product;
      _replacementQuantities[product.product.id] =
          (_replacementQuantities[product.product.id] ?? 0) + 1;
    });
  }

  bool _canSubmit(SaleDetail detail) {
    if (_returnQuantities.isEmpty) return false;
    if (_isExchange) {
      if (_replacementQuantities.isEmpty) return false;
      final breakdown = computeExchangeBreakdown(
        returnCredit: _returnCredit(detail),
        replacementTotal: _replacementTotal,
      );
      if (breakdown.balanceDue > 0) {
        final paid =
            double.tryParse(_balanceController.text.replaceAll(',', '.')) ?? 0;
        return paid >= breakdown.balanceDue - 0.005;
      }
    }
    return true;
  }

  Future<void> _commit() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final detail = await ref.read(saleDetailProvider(widget.saleId).future);
    final returnedLines = [
      for (final entry in _returnQuantities.entries)
        ReturnLineRequest(
          saleItemId: entry.key,
          productId: _productIdOfSaleItem(detail, entry.key),
          quantity: entry.value,
        ),
    ];
    setState(() => _saving = true);
    try {
      final repo = ref.read(refundsRepositoryProvider);
      final Object? result;
      if (_isExchange) {
        final breakdown = computeExchangeBreakdown(
          returnCredit: _returnCredit(detail),
          replacementTotal: _replacementTotal,
        );
        final paid =
            double.tryParse(_balanceController.text.replaceAll(',', '.')) ?? 0;
        final balancePayments = breakdown.balanceDue > 0
            ? [PaymentDraft(method: _method, amount: paid)]
            : const <PaymentDraft>[];
        result = await repo.createExchange(
          ExchangeRequest(
            originalSaleId: widget.saleId,
            returnedLines: returnedLines,
            replacements: [
              for (final entry in _replacementQuantities.entries)
                (productId: entry.key, quantity: entry.value),
            ],
            balancePayments: balancePayments,
            cashierId: user.id,
          ),
        );
      } else {
        result = await repo.createRefund(
          RefundRequest(
            originalSaleId: widget.saleId,
            lines: returnedLines,
            method: _method,
            reason: _reasonController.text.trim().isEmpty
                ? null
                : _reasonController.text.trim(),
            cashierId: user.id,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(result);
    } on RefundException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _productIdOfSaleItem(SaleDetail detail, String saleItemId) =>
      detail.items.where((e) => e.item.id == saleItemId).first.item.productId;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ReturnLineTile extends StatelessWidget {
  const _ReturnLineTile({
    required this.productName,
    required this.unitPrice,
    required this.remaining,
    required this.quantity,
    required this.onChanged,
  });

  final String productName;
  final double unitPrice;
  final double remaining;
  final double quantity;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(productName, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${formatMoney(unitPrice)} · ${remaining.toStringAsFixed(0)} returnable',
      ),
      trailing: quantity <= 0
          ? TextButton(
              onPressed: remaining > 0 ? () => onChanged(1) : null,
              child: const Text('Return'),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => onChanged(quantity - 1),
                ),
                SizedBox(
                  width: 26,
                  child: Text(
                    quantity.toStringAsFixed(0),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: quantity < remaining
                      ? () => onChanged(quantity + 1)
                      : null,
                ),
              ],
            ),
    );
  }
}

class _ReplacementTile extends StatelessWidget {
  const _ReplacementTile({
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.onChanged,
  });

  final String name;
  final double unitPrice;
  final double quantity;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(name, overflow: TextOverflow.ellipsis),
      subtitle: Text(formatMoney(unitPrice * quantity)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => onChanged(quantity - 1),
          ),
          SizedBox(
            width: 26,
            child: Text(
              quantity.toStringAsFixed(0),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => onChanged(quantity + 1),
          ),
        ],
      ),
    );
  }
}
