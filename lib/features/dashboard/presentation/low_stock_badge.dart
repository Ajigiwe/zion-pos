import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/features/dashboard/presentation/dashboard_providers.dart';

/// The count of products needing restock, shown on the Dashboard's sidebar
/// entry. Hidden entirely when nothing is low so the rail stays clean.
class LowStockBadge extends ConsumerWidget {
  const LowStockBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref
        .watch(lowStockCountProvider)
        .maybeWhen(data: (value) => value, orElse: () => 0);
    if (count <= 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: count == 1
          ? '1 product is low on stock'
          : '$count products are low on stock',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            '$count',
            style: TextStyle(
              color: scheme.onError,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
