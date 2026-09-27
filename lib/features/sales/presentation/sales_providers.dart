import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/features/sales/data/sales_repository.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';

final salesRepositoryProvider = Provider<SaleRepository>((ref) {
  return DriftSaleRepository(ref.watch(databaseProvider));
});

/// Completed sales for the history view.
final recentSalesProvider = StreamProvider<List<Sale>>((ref) {
  return ref.watch(salesRepositoryProvider).watchRecentSales();
});

final saleDetailProvider = FutureProvider.autoDispose
    .family<SaleDetail, String>(
      (ref, saleId) =>
          ref.watch(salesRepositoryProvider).loadSaleDetail(saleId),
    );
