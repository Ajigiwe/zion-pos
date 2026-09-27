import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/features/sales/domain/receipt_customization.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';

/// Manages reactive receipt customization settings across the application.
class ReceiptCustomizationController extends Notifier<ReceiptCustomization> {
  @override
  ReceiptCustomization build() => const ReceiptCustomization();

  Future<void> loadFromDb() async {
    try {
      state =
          await ref.read(settingsRepositoryProvider).loadReceiptCustomization();
    } catch (_) {
      // Fallback to defaults
    }
  }

  Future<void> save(
    ReceiptCustomization next, {
    required String actingUserId,
  }) async {
    await ref
        .read(settingsRepositoryProvider)
        .saveReceiptCustomization(next, actingUserId: actingUserId);
    state = next;
  }
}

final receiptCustomizationControllerProvider =
    NotifierProvider<
      ReceiptCustomizationController,
      ReceiptCustomization
    >(ReceiptCustomizationController.new);
