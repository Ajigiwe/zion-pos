import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/features/inventory/data/inventory_repository.dart';
import 'package:instrument_pos/features/inventory/presentation/stock_sheet_service.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(ref.watch(databaseProvider));
});

/// Ledger movements matching the current filter, live-updating on writes.
final movementsProvider = StreamProvider.autoDispose
    .family<List<MovementWithProduct>, MovementFilter>(
      (ref, filter) =>
          ref.watch(inventoryRepositoryProvider).watchMovements(filter),
    );

/// Native print / save-pdf for the stock-count sheet (faked in widget tests).
final stockSheetServiceProvider = Provider<StockSheetService>(
  (ref) => DesktopStockSheetService(),
);
