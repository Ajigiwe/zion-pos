import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/features/refunds/data/refunds_repository.dart';

final refundsRepositoryProvider = Provider<RefundsRepository>((ref) {
  return DriftRefundsRepository(ref.watch(databaseProvider));
});

final recentRefundsProvider = StreamProvider<List<RefundWithReceipt>>((ref) {
  return ref.watch(refundsRepositoryProvider).watchRefunds();
});

final recentExchangesProvider = StreamProvider<List<ExchangeWithReceipt>>((
  ref,
) {
  return ref.watch(refundsRepositoryProvider).watchExchanges();
});

/// saleItemId -> still-refundable quantity for an original sale.
final refundableQuantitiesProvider = FutureProvider.autoDispose
    .family<Map<String, double>, String>((ref, saleId) {
      return ref
          .watch(refundsRepositoryProvider)
          .remainingQuantitiesFor(saleId);
    });
