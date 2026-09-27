import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/features/dashboard/data/dashboard_repository.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(databaseProvider));
});

/// Today's takings, sale count and low-stock alerts. Auto-disposed, so it
/// re-reads whenever the Dashboard is opened; the page can also refresh.
final dashboardProvider = FutureProvider.autoDispose<DashboardSnapshot>((ref) {
  return ref.watch(dashboardRepositoryProvider).load();
});

/// Number of products that currently need restocking — the count shown on the
/// Dashboard's sidebar badge. Re-emits whenever the movement ledger, product
/// catalog or settings change, so a sale or adjustment updates the badge
/// without reopening the page.
final lowStockCountProvider = StreamProvider.autoDispose<int>((ref) {
  final repo = ref.watch(dashboardRepositoryProvider);
  final db = ref.watch(databaseProvider);
  return _watchLowStockCount(db, repo);
});

Stream<int> _watchLowStockCount(AppDatabase db, DashboardRepository repo) {
  final controller = StreamController<int>();
  final subscriptions = <StreamSubscription>[];

  Future<void> refresh() async {
    try {
      final items = await repo.lowStockProducts();
      if (!controller.isClosed) controller.add(items.length);
    } catch (_) {
      // Database not ready yet; the next change event retries.
    }
  }

  for (final stream in [
    db.select(db.products).watch(),
    db.select(db.stockMovements).watch(),
    db.select(db.settings).watch(),
  ]) {
    subscriptions.add(stream.listen((_) => refresh()));
  }
  refresh();

  controller.onCancel = () {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
  };
  return controller.stream;
}
