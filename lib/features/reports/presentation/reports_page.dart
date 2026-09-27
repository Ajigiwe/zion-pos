import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/auth/domain/roles.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/reports/domain/report_csv.dart';
import 'package:instrument_pos/features/reports/domain/report_models.dart';
import 'package:instrument_pos/features/reports/presentation/reports_providers.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final role = user == null ? null : Role.fromStorage(user.role);
    if (!(role?.can(Permission.viewReports) ?? false)) {
      return const _NoAccess();
    }

    final range = ref.watch(selectedReportRangeProvider);
    final report = ref.watch(reportDataProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Reports', style: Theme.of(context).textTheme.headlineSmall),
              SegmentedButton<TimelineRange>(
                segments: [
                  for (final value in TimelineRange.values)
                    ButtonSegment(value: value, label: Text(value.label)),
                ],
                selected: {range},
                onSelectionChanged: (selection) => ref
                    .read(selectedReportRangeProvider.notifier)
                    .select(selection.first),
              ),
              report.maybeWhen(
                data: (data) => data.isEmpty
                    ? const SizedBox.shrink()
                    : OutlinedButton.icon(
                        onPressed: () => _exportCsv(context, ref, data),
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('Export CSV'),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        Expanded(
          child: report.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                Center(child: Text('Could not load reports: $error')),
            data: (data) =>
                data.isEmpty ? const _EmptyPeriod() : _ReportBody(data: data),
          ),
        ),
      ],
    );
  }

  Future<void> _exportCsv(
    BuildContext context,
    WidgetRef ref,
    ReportData data,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final suggestedName = 'report-${data.range.label.replaceAll(' ', '-')}.csv';
    final saved = await ref
        .read(reportExportServiceProvider)
        .saveCsv(_buildFullCsv(data), suggestedName: suggestedName);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(saved ? 'Report exported.' : 'Export cancelled.')),
    );
  }

  String _buildFullCsv(ReportData data) {
    return [
      buildFinancialCsv(data),
      '',
      buildBreakdownCsv(
        title: 'Sales by Cashier',
        headers: const ['Cashier', 'Sales', 'Total (GHS)'],
        rows: [
          for (final row in data.byCashier)
            [row.cashierName, '${row.saleCount}', row.total.toStringAsFixed(2)],
        ],
      ),
      '',
      buildBreakdownCsv(
        title: 'Sales by Product',
        headers: const ['SKU', 'Product', 'Qty', 'Revenue (GHS)'],
        rows: [
          for (final row in data.byProduct)
            [
              row.sku,
              row.name,
              _qty(row.quantity),
              row.revenue.toStringAsFixed(2),
            ],
        ],
      ),
      '',
      buildBreakdownCsv(
        title: 'Refunds by Cashier',
        headers: const ['Cashier', 'Refunds', 'Total (GHS)'],
        rows: [
          for (final row in data.refundsByCashier)
            [row.cashierName, '${row.saleCount}', row.total.toStringAsFixed(2)],
        ],
      ),
      '',
      buildBreakdownCsv(
        title: 'Refunds by Product',
        headers: const ['Product', 'Qty', 'Amount (GHS)'],
        rows: [
          for (final row in data.refundsByProduct)
            [row.name, _qty(row.quantity), row.amount.toStringAsFixed(2)],
        ],
      ),
      '',
      buildBreakdownCsv(
        title: 'Refund Reasons',
        headers: const ['Reason', 'Refunds', 'Amount (GHS)'],
        rows: [
          for (final row in data.refundReasons)
            [row.reason, '${row.count}', row.amount.toStringAsFixed(2)],
        ],
      ),
    ].join('\n');
  }
}

String _qty(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

/// Shown to roles without `viewReports` (cashier, inventory manager).
class _NoAccess extends StatelessWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text('Reports', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'You do not have permission to view reports.\n'
            'Ask an owner, admin or manager.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

class _EmptyPeriod extends StatelessWidget {
  const _EmptyPeriod();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          const Text('No sales or refunds in this period.'),
          const SizedBox(height: 4),
          Text(
            'Try another range.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.data});

  final ReportData data;

  @override
  Widget build(BuildContext context) {
    final financial = data.financial;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        // IntrinsicHeight gives the four summary cards equal height; a plain
        // stretch would pass the ListView's infinite height down and crash.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'Total sales',
                  value: formatMoney(financial.grossSales),
                  caption: '${financial.saleCount} sale(s)',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  label: 'Discounts',
                  value: formatMoney(financial.discounts),
                  caption: 'given at the till',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  label: 'Refunds',
                  value: formatMoney(financial.refundsTotal),
                  caption: '${financial.refundCount} refund(s)',
                  error: financial.refundsTotal > 0.001,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  label: 'Net sales',
                  value: formatMoney(financial.netSales),
                  caption: 'sales − refunds',
                  emphasized: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionTitle('Payments received · ${data.range.label}'),
        _MethodListCard(
          entries: [
            for (final method in PaymentMethod.values)
              (
                method,
                financial.moneyByMethod(method),
                financial.paymentsByMethodCount(method),
              ),
          ],
          emptyText: 'No payments recorded in this period.',
        ),
        const SizedBox(height: 20),
        _SectionTitle('Refunds paid out'),
        _MethodListCard(
          entries: [
            for (final method in PaymentMethod.values)
              (
                method,
                financial.refundsByMethodTotal(method),
                financial.refundsByMethodCount(method),
              ),
          ],
          emptyText: 'No refunds recorded in this period.',
          errorWhenPositive: true,
        ),
        const SizedBox(height: 20),
        _SectionTitle('Sales by cashier'),
        _ReportTable(
          headers: const ['Cashier', 'Sales', 'Total'],
          numericColumns: const {1, 2},
          rows: [
            for (final row in data.byCashier)
              [row.cashierName, '${row.saleCount}', formatMoney(row.total)],
          ],
          emptyText: 'No sales in this period.',
        ),
        const SizedBox(height: 20),
        _SectionTitle('Sales by product'),
        _ReportTable(
          headers: const ['SKU', 'Product', 'Qty', 'Revenue'],
          numericColumns: const {2, 3},
          rows: [
            for (final row in data.byProduct)
              [row.sku, row.name, _qty(row.quantity), formatMoney(row.revenue)],
          ],
          emptyText: 'No products sold in this period.',
        ),
        const SizedBox(height: 20),
        _SectionTitle('Refunds by cashier'),
        _ReportTable(
          headers: const ['Cashier', 'Refunds', 'Total'],
          numericColumns: const {1, 2},
          rows: [
            for (final row in data.refundsByCashier)
              [row.cashierName, '${row.saleCount}', formatMoney(row.total)],
          ],
          emptyText: 'No refunds in this period.',
        ),
        const SizedBox(height: 20),
        _SectionTitle('Refunds by product'),
        _ReportTable(
          headers: const ['Product', 'Qty', 'Amount'],
          numericColumns: const {1, 2},
          rows: [
            for (final row in data.refundsByProduct)
              [row.name, _qty(row.quantity), formatMoney(row.amount)],
          ],
          emptyText: 'No refunded products in this period.',
        ),
        const SizedBox(height: 20),
        _SectionTitle('Refund reasons'),
        _ReportTable(
          headers: const ['Reason', 'Refunds', 'Amount'],
          numericColumns: const {1, 2},
          rows: [
            for (final row in data.refundReasons)
              [row.reason, '${row.count}', formatMoney(row.amount)],
          ],
          emptyText: 'No refunds in this period.',
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.caption,
    this.emphasized = false,
    this.error = false,
  });

  final String label;
  final String value;
  final String caption;
  final bool emphasized;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final valueColor = error
        ? scheme.error
        : emphasized
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(14),
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
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: emphasized
                  ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
                  : scheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, color: valueColor),
            ),
          ),
          const SizedBox(height: 2),
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

typedef _MethodEntry = (PaymentMethod, double, int);

class _MethodListCard extends StatelessWidget {
  const _MethodListCard({
    required this.entries,
    required this.emptyText,
    this.errorWhenPositive = false,
  });

  final List<_MethodEntry> entries;
  final String emptyText;
  final bool errorWhenPositive;

  @override
  Widget build(BuildContext context) {
    final visible = entries
        .where((entry) => entry.$2 != 0 || entry.$3 != 0)
        .toList();
    if (visible.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            emptyText,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(
                visible[i].$1 == PaymentMethod.cash
                    ? Icons.payments_outlined
                    : Icons.smartphone_outlined,
              ),
              title: Text(visible[i].$1.label),
              trailing: Text(
                '${formatMoney(visible[i].$2)} · ${visible[i].$3}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: errorWhenPositive && visible[i].$2 > 0.001
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({
    required this.headers,
    required this.rows,
    required this.numericColumns,
    required this.emptyText,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final Set<int> numericColumns;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (rows.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            emptyText,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.outline),
          ),
        ),
      );
    }
    TableRow headerRow() => TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      children: [
        for (var i = 0; i < headers.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              headers[i],
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.outline,
              ),
            ),
          ),
      ],
    );

    TableRow dataRow(List<String> cells) => TableRow(
      children: [
        for (var i = 0; i < cells.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              cells[i],
              overflow: TextOverflow.ellipsis,
              textAlign: numericColumns.contains(i)
                  ? TextAlign.right
                  : TextAlign.left,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: {
          for (var i = 0; i < headers.length; i++) i: const FlexColumnWidth(1),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: scheme.outlineVariant),
        ),
        children: [headerRow(), ...rows.map(dataRow)],
      ),
    );
  }
}
