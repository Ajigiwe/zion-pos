import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/features/dashboard/data/dashboard_repository.dart';
import 'package:instrument_pos/features/dashboard/presentation/dashboard_providers.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key, required this.onOpenInventory});

  final VoidCallback onOpenInventory;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(dashboardProvider);
    final today = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
          child: Row(
            children: [
              Text(
                'Dashboard',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(width: 12),
              Text(
                '${today.day} ${_months[today.month - 1]} ${today.year}',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(dashboardProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        Expanded(
          child: snapshot.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load the dashboard: $error'),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () => ref.invalidate(dashboardProvider),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
            data: (data) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _StatCard(
                  icon: Icons.account_balance_wallet_outlined,
                  label: "Today's takings",
                  amount: formatMoney(data.takingsTotal),
                  caption: 'Cash + Mobile Money · after refunds',
                  emphasized: true,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.payments_outlined,
                        label: 'Cash',
                        amount: formatMoney(data.cashTotal),
                        caption: '${data.cashPayments} payment(s) today',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.smartphone_outlined,
                        label: 'Mobile Money',
                        amount: formatMoney(data.mobileMoneyTotal),
                        caption: '${data.mobileMoneyPayments} payment(s) today',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _RefundsCard(snapshot: data),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Sales today',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text(
                      '${data.saleCount} completed',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Low stock alerts',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (data.lowStock.isEmpty)
                  const _HealthyCard()
                else
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < data.lowStock.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _LowStockTile(product: data.lowStock[i]),
                        ],
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: onOpenInventory,
                              icon: const Icon(Icons.arrow_forward, size: 16),
                              label: const Text('Open Inventory'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.amount,
    required this.caption,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final String amount;
  final String caption;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: emphasized ? scheme.primaryContainer : scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: emphasized
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: emphasized ? scheme.onPrimaryContainer : scheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: emphasized
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: emphasized
                    ? scheme.onPrimaryContainer
                    : scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: emphasized
                  ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
                  : scheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _RefundsCard extends StatelessWidget {
  const _RefundsCard({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.assignment_return_outlined,
                  size: 18,
                  color: scheme.error,
                ),
                const SizedBox(width: 6),
                Text(
                  'Refunds today',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${snapshot.cashRefundCount + snapshot.mobileMoneyRefundCount} '
                  'refund(s) total',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _RefundColumn(
                    label: 'Cash',
                    amount: snapshot.cashRefunds,
                    count: snapshot.cashRefundCount,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RefundColumn(
                    label: 'Mobile Money',
                    amount: snapshot.mobileMoneyRefunds,
                    count: snapshot.mobileMoneyRefundCount,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RefundColumn extends StatelessWidget {
  const _RefundColumn({
    required this.label,
    required this.amount,
    required this.count,
  });

  final String label;
  final double amount;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.outline),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatMoney(amount),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: amount > 0.001 ? scheme.error : scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$count refund(s) today',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.outline),
        ),
      ],
    );
  }
}

class _HealthyCard extends StatelessWidget {
  const _HealthyCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'All stock levels are healthy.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LowStockTile extends StatelessWidget {
  const _LowStockTile({required this.product});

  final LowStockProduct product;

  String get _quantityLabel {
    final value = product.stock;
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        product.isOutOfStock
            ? Icons.remove_circle_outline
            : Icons.warning_amber_rounded,
        color: product.isOutOfStock ? scheme.error : scheme.tertiary,
      ),
      title: Text(product.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        product.isOutOfStock
            ? 'Out of stock'
            : 'Reorder at ${product.reorderLevel.toStringAsFixed(0)}',
      ),
      trailing: Text(
        '$_quantityLabel left',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: product.isOutOfStock ? scheme.error : scheme.onSurface,
        ),
      ),
    );
  }
}
