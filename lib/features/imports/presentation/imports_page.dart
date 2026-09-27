import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/auth/domain/roles.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/imports/data/import_repository.dart';
import 'package:instrument_pos/features/imports/domain/import_document.dart';
import 'package:instrument_pos/features/imports/presentation/import_file_service.dart';
import 'package:instrument_pos/features/imports/presentation/import_providers.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';

class ImportsPage extends ConsumerStatefulWidget {
  const ImportsPage({super.key});

  @override
  ConsumerState<ImportsPage> createState() => _ImportsPageState();
}

class _ImportsPageState extends ConsumerState<ImportsPage> {
  PickedImportFile? _file;
  ParsedImport? _parsed;
  ImportMode _mode = ImportMode.addStock;
  ImportAnalysis? _analysis;
  String? _fatal;
  bool _analyzing = false;
  bool _committing = false;

  @override
  void dispose() {
    super.dispose();
  }

  bool get _hasFile => _file != null;

  Future<void> _pickFile() async {
    final service = ref.read(importFileServiceProvider);
    final picked = await service.pickFile();
    if (picked == null || !mounted) return;
    final parsed = parseImportFile(fileName: picked.name, bytes: picked.bytes);
    if (parsed == null) {
      setState(() {
        _file = null;
        _parsed = null;
        _analysis = null;
        _fatal = 'Unsupported file. Choose a .csv or .xlsx spreadsheet.';
      });
      return;
    }
    setState(() {
      _file = picked;
      _parsed = parsed;
      _analysis = null;
      _fatal = null;
    });
    await _analyze();
  }

  Future<void> _analyze() async {
    final parsed = _parsed;
    if (parsed == null) return;
    setState(() {
      _analyzing = true;
      _analysis = null;
    });
    try {
      final analysis = await ref
          .read(bulkImportRepositoryProvider)
          .analyze(document: parsed, mode: _mode);
      if (mounted) setState(() => _analysis = analysis);
    } catch (error) {
      if (mounted) {
        setState(() => _fatal = 'Analysis failed: $error');
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _setMode(ImportMode mode) async {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    await _analyze();
  }

  Future<void> _commit() async {
    final parsed = _parsed;
    final analysis = _analysis;
    if (parsed == null || analysis == null || !analysis.canImport) return;
    final user = ref.read(currentUserProvider);
    setState(() => _committing = true);
    try {
      final result = await ref
          .read(bulkImportRepositoryProvider)
          .commit(document: parsed, analysis: analysis, userId: user?.id);
      if (!mounted) return;
      final movements = switch (analysis.mode) {
        ImportMode.productOnly => '',
        ImportMode.addStock ||
        ImportMode.openingStock => ' · ${formatUnits(result.unitsIn)} units in',
        ImportMode.setPhysical =>
          ' · ${formatUnits(result.unitsIn)} in / '
              '${formatUnits(result.unitsOut)} out',
      };
      _showSnack(
        '${result.batch.batchNumber} imported: '
        '${result.productsCreated} new, ${result.productsUpdated} updated, '
        '${result.batch.failedRows} row(s) failed'
        '$movements.',
      );
      setState(() {
        _file = null;
        _parsed = null;
        _analysis = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _fatal = 'Import failed: $error');
      }
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _reset() {
    setState(() {
      _file = null;
      _parsed = null;
      _analysis = null;
      _fatal = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final role = user == null ? null : Role.fromStorage(user.role);
    final canCatalog = role?.can(Permission.productManage) ?? false;
    final canStock = role?.can(Permission.inventoryControl) ?? false;
    final canAdjust = role?.can(Permission.stockAdjustment) ?? false;

    Set<ImportMode> allowedModes() {
      return {
        if (canCatalog) ImportMode.productOnly,
        if (canStock) ImportMode.addStock,
        if (canStock) ImportMode.openingStock,
        if (canAdjust) ImportMode.setPhysical,
      };
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Imports', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 2),
        Text(
          'Bulk-import products and stock from CSV or Excel — every import is '
          'validated, previewed, then committed as a batch (§19–§23).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 16),
        if (!canCatalog && !canStock && !canAdjust)
          _LockedNotice()
        else ...[
          _ImportActionBar(
            onChoose: _hasFile ? null : _pickFile,
            onTemplate: () async {
              final saved = await ref
                  .read(importFileServiceProvider)
                  .saveTemplate();
              if (saved && mounted) _showSnack('Template saved.');
            },
          ),
          if (_fatal != null) _ErrorBanner(message: _fatal!, onDismiss: _reset),
          if (_hasFile && _fatal == null)
            _ImportPanel(
              fileName: _file!.name,
              allowedModes: allowedModes(),
              mode: _mode,
              onModeChanged: _setMode,
              analyzing: _analyzing,
              analysis: _analysis,
              committing: _committing,
              onViewErrors: () => _showErrorsDialog(_analysis!.issues),
              onCommit: _analysis?.canImport == true ? _commit : null,
              onCancel: _committing ? null : _reset,
            ),
        ],
        const SizedBox(height: 24),
        Text('Import history', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const _BatchHistory(),
      ],
    );
  }

  void _showErrorsDialog(List<RowIssue> issues) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Import errors (${issues.length})'),
        content: SizedBox(
          width: 520,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: issues.length,
            itemBuilder: (context, index) {
              final issue = issues[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  issue.display,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Header buttons: pick a file, or download the CSV template.
class _ImportActionBar extends StatelessWidget {
  const _ImportActionBar({required this.onChoose, required this.onTemplate});

  final VoidCallback? onChoose;
  final VoidCallback onTemplate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New import', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Columns: Item Name, Price (GHC), Qty — optional: SKU, Barcode, Category, '
              'Brand, Cost Price, Tax Rate (%), Reorder Level, Tracking.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onChoose,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Choose file…'),
                ),
                OutlinedButton.icon(
                  onPressed: onTemplate,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download CSV template'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Preview of the parsed file: mode picker, summary counts, and commit.
class _ImportPanel extends StatelessWidget {
  const _ImportPanel({
    required this.fileName,
    required this.allowedModes,
    required this.mode,
    required this.onModeChanged,
    required this.analyzing,
    required this.analysis,
    required this.committing,
    required this.onViewErrors,
    required this.onCommit,
    required this.onCancel,
  });

  final String fileName;
  final Set<ImportMode> allowedModes;
  final ImportMode mode;
  final ValueChanged<ImportMode> onModeChanged;
  final bool analyzing;
  final ImportAnalysis? analysis;
  final bool committing;
  final VoidCallback onViewErrors;
  final VoidCallback? onCommit;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = analysis; // local so flow analysis can promote it
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    fileName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (onCancel != null)
                  TextButton(onPressed: onCancel, child: const Text('Discard')),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'What does Quantity mean?',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final candidate in ImportMode.values)
                  if (allowedModes.contains(candidate))
                    ChoiceChip(
                      label: Text(candidate.label),
                      selected: candidate == mode,
                      onSelected: committing
                          ? null
                          : (_) => onModeChanged(candidate),
                    ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              mode.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 14),
            if (analyzing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (current == null)
              const SizedBox.shrink()
            else if (current.problems.isNotEmpty)
              _ErrorBanner(
                message: current.problems.join('\n'),
                onDismiss: null,
              )
            else
              _PreviewSummary(analysis: current),
            if (current != null && current.issues.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: committing ? null : onViewErrors,
                icon: const Icon(Icons.report_problem_outlined, size: 18),
                label: Text('View errors (${current.issueCount})'),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: committing || (onCommit == null) ? null : onCommit,
                  icon: committing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    committing
                        ? 'Importing…'
                        : analysis == null
                        ? 'Import'
                        : 'Import ${analysis!.validRows} row(s)',
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

/// Counts shown before committing, mirroring the design's preview (§23).
class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary({required this.analysis});

  final ImportAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stat(String label, String value, {Color? color}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            stat('Valid rows', '${analysis.validRows}'),
            stat('New products', '${analysis.newProducts}'),
            stat('Updates', '${analysis.existingProducts}'),
            if (analysis.categoriesToCreate > 0)
              stat('Categories to create', '${analysis.categoriesToCreate}'),
            if (analysis.brandsToCreate > 0)
              stat('Brands to create', '${analysis.brandsToCreate}'),
            if (analysis.mode.touchesStock) ...[
              if (analysis.unitsIn > 0)
                stat(
                  'Units in',
                  '+${formatUnits(analysis.unitsIn)}',
                  color: theme.colorScheme.primary,
                ),
              if (analysis.unitsOut > 0)
                stat(
                  'Units out',
                  '−${formatUnits(analysis.unitsOut)}',
                  color: theme.colorScheme.error,
                ),
              if (analysis.noChangeRows > 0)
                stat('Already correct', '${analysis.noChangeRows}'),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Stock is never edited directly — this import will create ledger '
          'movements only (§2.3).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _LockedNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: theme.colorScheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your role cannot import products or stock. Ask an owner, '
                'admin or manager to run the import (§31).',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.onDismiss});

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline,
                size: 20,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Committed import batches (§20).
class _BatchHistory extends ConsumerWidget {
  const _BatchHistory();

  static const _typeLabels = {
    'PRODUCT_IMPORT': 'Products',
    'OPENING_STOCK': 'Opening stock',
    'BULK_STOCK': 'Stock',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final batches = ref.watch(importBatchesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: batches.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error: $error'),
          ),
          data: (items) => items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No imports yet. Pick a spreadsheet to create the first batch.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final batch in items)
                      _BatchRow(
                        batch: batch,
                        typeLabel:
                            _typeLabels[batch.importType] ?? batch.importType,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.batch, required this.typeLabel});

  final ImportBatch batch;
  final String typeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = ImportMode.fromStorage(batch.mode);
    final failed = batch.failedRows;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: const Icon(Icons.upload_file, size: 18),
      ),
      title: Text(
        '${batch.batchNumber} · $typeLabel',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${batch.fileName} · ${mode.label} · '
        '${formatDateTime(batch.createdAt)}',
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${batch.successfulRows}/${batch.totalRows} rows',
        style: theme.textTheme.bodySmall?.copyWith(
          color: failed > 0
              ? theme.colorScheme.error
              : theme.colorScheme.outline,
          fontWeight: failed > 0 ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}
