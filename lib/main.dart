import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/app_root.dart';
import 'package:instrument_pos/core/app_restart.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';
import 'package:instrument_pos/features/settings/presentation/printer_settings_providers.dart';
import 'package:instrument_pos/features/settings/presentation/receipt_settings_providers.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';
import 'package:instrument_pos/features/settings/presentation/theme_settings_providers.dart';
import 'package:instrument_pos/core/database/lan_sync_service.dart';
import 'package:instrument_pos/core/database/workstation_config.dart';
import 'package:instrument_pos/features/settings/presentation/network_settings_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WorkstationConfig.load();

  runApp(
    // A new key after a database restore remounts the whole ProviderScope,
    // giving the app a fresh container and database connection.
    ValueListenableBuilder<int>(
      valueListenable: appRestartCount,
      builder: (context, count, _) => ProviderScope(
        key: ValueKey('app-$count'),
        child: const InstrumentPosApp(),
      ),
    ),
  );
}

class InstrumentPosApp extends ConsumerWidget {
  const InstrumentPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeName = ref.watch(storeInfoControllerProvider).name;
    final themeSettings = ref.watch(themeSettingsControllerProvider);

    final lightColorScheme = ColorScheme.fromSeed(
      seedColor: themeSettings.primaryColor,
      brightness: Brightness.light,
    );
    final darkColorScheme = ColorScheme.fromSeed(
      seedColor: themeSettings.primaryColor,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: storeName,
      debugShowCheckedModeBanner: false,
      themeMode: themeSettings.themeMode,
      theme: ThemeData(
        colorScheme: lightColorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      darkTheme: ThemeData(
        colorScheme: darkColorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      // Loads the persisted store profile, receipt toggles, and theme shortly after
      // startup; the controller keeps compile-time defaults meanwhile.
      home: const _StoreProfileBootstrap(child: AppRoot()),
    );
  }
}

class _StoreProfileBootstrap extends ConsumerStatefulWidget {
  const _StoreProfileBootstrap({required this.child});

  final Widget child;

  @override
  ConsumerState<_StoreProfileBootstrap> createState() =>
      _StoreProfileBootstrapState();
}

class _StoreProfileBootstrapState
    extends ConsumerState<_StoreProfileBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storeInfoControllerProvider.notifier).loadFromDb();
      ref.read(receiptCustomizationControllerProvider.notifier).loadFromDb();
      ref.read(themeSettingsControllerProvider.notifier).loadFromDb();
      ref.read(printerSettingsControllerProvider.notifier).loadFromDb();
      ref.read(networkSettingsControllerProvider.notifier).loadFromDb();
      ref.read(lanSyncServiceProvider);
      if (kDebugMode) {
        // Debug builds only: populate the catalog from the store's stock sheet
        // once, so the POS can be exercised before real data arrives.
        unawaited(
          ref.read(sampleCatalogSeederProvider).seedIfNeeded().then((created) {
            if (created > 0) {
              debugPrint('Seeded $created sample products (test data).');
            }
          }),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
