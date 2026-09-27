import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/settings/data/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(databaseProvider));
});

/// The store profile shown on receipts and in branding. It starts as the
/// compile-time [kStoreInfo], is replaced with the persisted values when
/// [StoreInfoController.loadFromDb] runs at startup, and updates live on
/// save — so receipts always carry the current letterhead without any widget
/// needing to await the database.
class StoreInfoController extends Notifier<StoreInfo> {
  @override
  StoreInfo build() => kStoreInfo;

  Future<void> loadFromDb() async {
    try {
      state = await ref.read(settingsRepositoryProvider).loadStoreInfo();
    } catch (_) {
      // Keep the defaults; the settings UI surfaces any write errors on save.
    }
  }

  Future<void> save(StoreInfo next, {required String actingUserId}) async {
    await ref
        .read(settingsRepositoryProvider)
        .updateStoreInfo(next, actingUserId: actingUserId);
    state = next;
  }
}

final storeInfoControllerProvider =
    NotifierProvider<StoreInfoController, StoreInfo>(StoreInfoController.new);

/// The global low-stock alert threshold. Re-read whenever the Settings page
/// (or Dashboard) needs it; invalidated after a save.
final lowStockThresholdProvider = FutureProvider<double>(
  (ref) => ref.watch(settingsRepositoryProvider).loadLowStockThreshold(),
);
