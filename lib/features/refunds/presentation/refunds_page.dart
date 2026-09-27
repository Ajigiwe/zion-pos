import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/auth/domain/roles.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/refunds/domain/refund_models.dart';
import 'package:instrument_pos/features/refunds/presentation/refund_flow_page.dart';
import 'package:instrument_pos/features/refunds/presentation/refunds_providers.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';
import 'package:instrument_pos/features/sales/presentation/receipt_print_service.dart';
import 'package:instrument_pos/features/sales/presentation/receipt_view.dart';
import 'package:instrument_pos/features/sales/presentation/sales_providers.dart';
import 'package:instrument_pos/features/settings/presentation/receipt_settings_providers.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';

enum _RefundsMode { newFlow, history }

class RefundsPage extends ConsumerStatefulWidget {
  const RefundsPage({super.key});

  @override
  ConsumerState<RefundsPage> createState() => _RefundsPageState();
}

class _RefundsPageState extends ConsumerState<RefundsPage> {
  _RefundsMode _mode = _RefundsMode.newFlow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Refunds & Exchanges',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              SegmentedButton<_RefundsMode>(
                segments: const [
                  ButtonSegment(
                    value: _RefundsMode.newFlow,
                    label: Text('New'),
                    icon: Icon(Icons.assignment_return_outlined),
                  ),
                  ButtonSegment(
                    value: _RefundsMode.history,
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
        // Center the sale picker / history so rows do not stretch across
        // ultrawide windows.
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: _mode == _RefundsMode.newFlow
                  ? const _SalePicker()
                  : const _RefundHistory(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lists completed sales so the cashier can start a refund or exchange.
class _SalePicker extends ConsumerWidget {
  const _SalePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final role = user == null ? null : Role.fromStorage(user.role);
    final canRefund = role?.can(Permission.refund) ?? false;
    final canExchange = role?.can(Permission.exchange) ?? false;

    final sales = ref.watch(recentSalesProvider);
    return sales.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No sales yet.\nComplete a sale before refunding or exchanging.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final sale = items[index];
            return ListTile(
              title: Text('${sale.receiptNumber} · ${formatMoney(sale.total)}'),
              subtitle: Text(formatDateTime(sale.createdAt)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: canRefund
                        ? () => _startFlow(context, ref, sale, RefundFlowMode.refund)
                        : null,
                    child: const Text('Refund'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: canExchange
                        ? () =>
                              _startFlow(context, ref, sale, RefundFlowMode.exchange)
                        : null,
                    child: const Text('Exchange'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startFlow(
    BuildContext context,
    WidgetRef ref,
    Sale sale,
    RefundFlowMode mode,
  ) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => RefundFlowPage(saleId: sale.id, mode: mode),
      ),
    );
    if (!context.mounted || result == null) return;

    final repo = ref.read(refundsRepositoryProvider);
    final store = ref.read(storeInfoControllerProvider);
    final custom = ref.read(receiptCustomizationControllerProvider);

    if (result is CompletedRefund) {
      final receipt = await repo.getRefundReceipt(
        result.refundId,
        store: store,
        customization: custom,
      );
      if (!context.mounted) return;
      _showReceiptDialog(context, ref, receipt);
    } else if (result is CompletedExchange) {
      final receipt = await repo.getExchangeReceipt(
        result.exchangeId,
        store: store,
        customization: custom,
      );
      if (!context.mounted) return;
      _showReceiptDialog(context, ref, receipt);
    }
  }
}

class _RefundHistory extends ConsumerWidget {
  const _RefundHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refunds = ref.watch(recentRefundsProvider);
    final exchanges = ref.watch(recentExchangesProvider);
    final repo = ref.read(refundsRepositoryProvider);
    final store = ref.watch(storeInfoControllerProvider);
    final custom = ref.watch(receiptCustomizationControllerProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Text('Exchanges', style: Theme.of(context).textTheme.titleSmall),
        exchanges.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('Error: $error'),
          data: (items) => items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No exchanges yet.'),
                )
              : Column(
                  children: [
                    for (final item in items)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.swap_horiz),
                        title: Text(
                          '${item.exchange.exchangeNumber} — replacement '
                          '${item.replacementReceiptNumber}',
                        ),
                        subtitle: Text(
                          'Original ${item.saleReceiptNumber} · '
                          '${formatDateTime(item.exchange.createdAt)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.exchange.difference >= 0
                                  ? 'Paid ${formatMoney(item.exchange.difference)}'
                                  : 'Refunded ${formatMoney(-item.exchange.difference)}',
                            ),
                            IconButton(
                              icon: const Icon(Icons.receipt_long_outlined),
                              tooltip: 'View Receipt',
                              onPressed: () async {
                                final receipt = await repo.getExchangeReceipt(
                                  item.exchange.id,
                                  store: store,
                                  customization: custom,
                                );
                                if (context.mounted) {
                                  _showReceiptDialog(context, ref, receipt);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const Divider(height: 28),
        Text('Refunds', style: Theme.of(context).textTheme.titleSmall),
        refunds.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('Error: $error'),
          data: (items) => items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No refunds yet.'),
                )
              : Column(
                  children: [
                    for (final item in items)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.replay),
                        title: Text(
                          '${item.refund.refundNumber} — '
                          '${formatMoney(item.refund.amount)} '
                          '(${item.refund.refundMethod.label})',
                        ),
                        subtitle: Text(
                          'Sale ${item.saleReceiptNumber} · '
                          '${formatDateTime(item.refund.createdAt)}'
                          '${item.refund.reason == null ? '' : ' · ${item.refund.reason}'}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.receipt_long_outlined),
                          tooltip: 'View Receipt',
                          onPressed: () async {
                            final receipt = await repo.getRefundReceipt(
                              item.refund.id,
                              store: store,
                              customization: custom,
                            );
                            if (context.mounted) {
                              _showReceiptDialog(context, ref, receipt);
                            }
                          },
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

void _showReceiptDialog(
  BuildContext context,
  WidgetRef ref,
  ReceiptContent content,
) {
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReceiptView(content: content),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final printed =
                            await printReceipt(ref, content: content);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(
                                  printed
                                      ? 'Receipt ${content.receiptNumber} printed.'
                                      : 'Print cancelled.',
                                ),
                              ),
                            );
                        }
                      },
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Print'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
