import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';
import 'package:instrument_pos/features/audit/presentation/audit_providers.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';

/// Read-only trail of who did what (§32). Shown only to owners/admins.
class AuditCard extends ConsumerWidget {
  const AuditCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = ref.watch(auditLogsProvider);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.security_outlined,
                    color: Color(0xFF7C3AED),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Audit log',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Who did what, and when — this record cannot be edited (§32).',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 12),
            entries.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('Error: $error'),
              data: (items) => items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'No activity recorded yet.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF94A3B8),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 440),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) =>
                            _AuditRow(entry: items[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});

  final AuditEntry entry;

  static String _label(String action) {
    final words = action.toLowerCase().split('_');
    return words
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final log = entry.log;
    final destructive = log.action == 'LOGIN_FAILED' ||
        log.action == 'USER_DEACTIVATED' ||
        log.action == 'STOCK_ADJUSTMENT';
    final color = destructive
        ? const Color(0xFFEF4444)
        : const Color(0xFF0284C7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withOpacity(0.12),
            child: Icon(
              log.action == 'LOGIN' || log.action == 'LOGIN_FAILED'
                  ? Icons.login
                  : Icons.receipt_long_outlined,
              size: 15,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label(log.action),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (entry.userName != null || log.details != null)
                  Text(
                    [
                      if (entry.userName != null) '@${entry.userName}',
                      if (log.details != null) log.details!,
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text(
            formatDateTime(log.createdAt),
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
