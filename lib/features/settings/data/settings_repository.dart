import 'package:drift/drift.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';
import 'package:instrument_pos/features/sales/domain/receipt_customization.dart';
import 'package:instrument_pos/features/settings/domain/app_theme_settings.dart';
import 'package:instrument_pos/features/settings/domain/printer_settings.dart';
import 'package:instrument_pos/features/settings/domain/network_settings.dart';

/// Reads and writes the store profile (name/address/phone) that is stamped on
/// receipts. Values live in the generic key/value `settings` table; the
/// compile-time [kStoreInfo] only seeds the defaults for a fresh install.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const _storeKeys = [
    StoreSettingKeys.name,
    StoreSettingKeys.address,
    StoreSettingKeys.phone,
  ];

  Future<StoreInfo> loadStoreInfo() async {
    final rows = await (_db.select(
      _db.settings,
    )..where((s) => s.key.isIn(_storeKeys))).get();
    return _toStoreInfo(rows);
  }

  /// Live profile for screens that want to react to changes.
  Stream<StoreInfo> watchStoreInfo() {
    return (_db.select(
      _db.settings,
    )..where((s) => s.key.isIn(_storeKeys))).watch().map(_toStoreInfo);
  }

  /// Persists the profile and records who changed it, atomically (§39) — the
  /// audit row rolls back together with the settings if anything fails.
  Future<void> updateStoreInfo(StoreInfo info, {required String actingUserId}) {
    return _db.transaction(() async {
      final now = DateTime.now();
      await _upsert(StoreSettingKeys.name, info.name, now);
      await _upsert(StoreSettingKeys.address, info.address, now);
      await _upsert(StoreSettingKeys.phone, info.phone, now);
      await AuditRepository(_db).log(
        action: AuditAction.storeDetailsUpdated,
        userId: actingUserId,
        entityType: 'settings',
        details: 'Store details updated to “${info.name}”',
      );
    });
  }

  Future<void> _upsert(String key, String value, DateTime now) {
    return (_db.into(_db.settings)).insertOnConflictUpdate(
      SettingsCompanion(
        key: Value(key),
        value: Value(value),
        updatedAt: Value(now),
      ),
    );
  }

  /// The global low-stock alert threshold ([kDefaultLowStockThreshold] until
  /// saved). Products with their own reorder level ignore it.
  Future<double> loadLowStockThreshold() async {
    final row =
        await (_db.select(_db.settings)
              ..where((s) => s.key.equals(StoreSettingKeys.lowStockThreshold)))
            .getSingleOrNull();
    final parsed = double.tryParse(row?.value ?? '');
    return parsed == null || parsed < 0 ? kDefaultLowStockThreshold : parsed;
  }

  /// Persists the threshold and records who changed it, atomically.
  Future<void> saveLowStockThreshold(
    double value, {
    required String actingUserId,
  }) {
    String label(double v) =>
        v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return _db.transaction(() async {
      await _upsert(
        StoreSettingKeys.lowStockThreshold,
        value.toString(),
        DateTime.now(),
      );
      await AuditRepository(_db).log(
        action: AuditAction.storeDetailsUpdated,
        userId: actingUserId,
        entityType: 'settings',
        details: 'Low stock threshold set to ${label(value)} units',
      );
    });
  }

  /// Loads the persisted receipt customization toggles and text.
  Future<ReceiptCustomization> loadReceiptCustomization() async {
    final rows = await (_db.select(
      _db.settings,
    )..where((s) => s.key.isIn(ReceiptSettingKeys.allKeys))).get();
    return _toReceiptCustomization(rows);
  }

  /// Live receipt customization stream.
  Stream<ReceiptCustomization> watchReceiptCustomization() {
    return (_db.select(
      _db.settings,
    )..where((s) => s.key.isIn(ReceiptSettingKeys.allKeys)))
        .watch()
        .map(_toReceiptCustomization);
  }

  /// Persists the receipt customization preferences atomically with audit logging.
  Future<void> saveReceiptCustomization(
    ReceiptCustomization customization, {
    required String actingUserId,
  }) {
    return _db.transaction(() async {
      final now = DateTime.now();
      await _upsert(
        ReceiptSettingKeys.showStoreName,
        customization.showStoreName.toString(),
        now,
      );
      await _upsert(
        ReceiptSettingKeys.showStoreAddress,
        customization.showStoreAddress.toString(),
        now,
      );
      await _upsert(
        ReceiptSettingKeys.showStorePhone,
        customization.showStorePhone.toString(),
        now,
      );
      await _upsert(
        ReceiptSettingKeys.headerCustomText,
        customization.headerCustomText,
        now,
      );
      await _upsert(
        ReceiptSettingKeys.showCashierName,
        customization.showCashierName.toString(),
        now,
      );
      await _upsert(
        ReceiptSettingKeys.showItemPriceMath,
        customization.showItemPriceMath.toString(),
        now,
      );
      await _upsert(
        ReceiptSettingKeys.showTax,
        customization.showTax.toString(),
        now,
      );
      await _upsert(
        ReceiptSettingKeys.showDiscount,
        customization.showDiscount.toString(),
        now,
      );
      await _upsert(
        ReceiptSettingKeys.showPaymentBreakdown,
        customization.showPaymentBreakdown.toString(),
        now,
      );
      await _upsert(
        ReceiptSettingKeys.showChangeDue,
        customization.showChangeDue.toString(),
        now,
      );
      await _upsert(
        ReceiptSettingKeys.footerMessage,
        customization.footerMessage,
        now,
      );
      await _upsert(
        ReceiptSettingKeys.showBarcode,
        customization.showBarcode.toString(),
        now,
      );
      await _upsert(
        ReceiptSettingKeys.showCustomerSignature,
        customization.showCustomerSignature.toString(),
        now,
      );
      await _upsert(
        ReceiptSettingKeys.paperWidth,
        customization.paperWidth,
        now,
      );
      await _upsert(
        ReceiptSettingKeys.sideMargin,
        customization.sideMargin.toString(),
        now,
      );
      await _upsert(
        ReceiptSettingKeys.bottomFeedSpace,
        customization.bottomFeedSpace.toString(),
        now,
      );
      await AuditRepository(_db).log(
        action: AuditAction.storeDetailsUpdated,
        userId: actingUserId,
        entityType: 'settings',
        details: 'Receipt layout preferences updated',
      );
    });
  }

  /// Loads the persisted theme mode and color settings.
  Future<AppThemeSettings> loadThemeSettings() async {
    final rows = await (_db.select(
      _db.settings,
    )..where((s) => s.key.isIn(ThemeSettingKeys.allKeys))).get();
    return _toThemeSettings(rows);
  }

  /// Live theme settings stream.
  Stream<AppThemeSettings> watchThemeSettings() {
    return (_db.select(
      _db.settings,
    )..where((s) => s.key.isIn(ThemeSettingKeys.allKeys)))
        .watch()
        .map(_toThemeSettings);
  }

  /// Persists theme settings atomically with audit logging.
  Future<void> saveThemeSettings(
    AppThemeSettings themeSettings, {
    required String actingUserId,
  }) {
    return _db.transaction(() async {
      final now = DateTime.now();
      await _upsert(
        ThemeSettingKeys.themeMode,
        themeSettings.themeModeString,
        now,
      );
      await _upsert(
        ThemeSettingKeys.themeColor,
        themeSettings.primaryColorHex,
        now,
      );
      await _upsert(
        ThemeSettingKeys.themePreset,
        themeSettings.presetId,
        now,
      );
      await AuditRepository(_db).log(
        action: AuditAction.storeDetailsUpdated,
        userId: actingUserId,
        entityType: 'settings',
        details:
            'Theme updated to ${themeSettings.themeModeString} mode (${themeSettings.presetId})',
      );
    });
  }

  /// Loads the persisted printer hardware configuration.
  Future<PrinterSettings> loadPrinterSettings() async {
    final rows = await (_db.select(
      _db.settings,
    )..where((s) => s.key.isIn(PrinterSettingKeys.allKeys))).get();
    return _toPrinterSettings(rows);
  }

  /// Live printer settings stream.
  Stream<PrinterSettings> watchPrinterSettings() {
    return (_db.select(
      _db.settings,
    )..where((s) => s.key.isIn(PrinterSettingKeys.allKeys)))
        .watch()
        .map(_toPrinterSettings);
  }

  /// Persists printer settings atomically with audit logging.
  Future<void> savePrinterSettings(
    PrinterSettings printerSettings, {
    required String actingUserId,
  }) {
    return _db.transaction(() async {
      final now = DateTime.now();
      await _upsert(
        PrinterSettingKeys.selectedPrinterUrl,
        printerSettings.selectedPrinterUrl ?? '',
        now,
      );
      await _upsert(
        PrinterSettingKeys.selectedPrinterName,
        printerSettings.selectedPrinterName ?? '',
        now,
      );
      await _upsert(
        PrinterSettingKeys.directPrinting,
        printerSettings.directPrinting.toString(),
        now,
      );
      await AuditRepository(_db).log(
        action: AuditAction.storeDetailsUpdated,
        userId: actingUserId,
        entityType: 'settings',
        details:
            'Active printer updated to "${printerSettings.selectedPrinterName ?? 'System Default'}" (direct: ${printerSettings.directPrinting})',
      );
    });
  }

  /// Loads the persisted LAN multi-register network configuration.
  Future<NetworkSettings> loadNetworkSettings() async {
    final rows = await (_db.select(
      _db.settings,
    )..where((s) => s.key.isIn(NetworkSettingKeys.allKeys))).get();
    return _toNetworkSettings(rows);
  }

  /// Live network settings stream.
  Stream<NetworkSettings> watchNetworkSettings() {
    return (_db.select(
      _db.settings,
    )..where((s) => s.key.isIn(NetworkSettingKeys.allKeys)))
        .watch()
        .map(_toNetworkSettings);
  }

  /// Persists network settings atomically with audit logging.
  Future<void> saveNetworkSettings(
    NetworkSettings networkSettings, {
    required String actingUserId,
  }) {
    return _db.transaction(() async {
      final now = DateTime.now();
      await _upsert(
        NetworkSettingKeys.stationMode,
        networkSettings.mode.name,
        now,
      );
      await _upsert(
        NetworkSettingKeys.hostPort,
        networkSettings.hostPort.toString(),
        now,
      );
      await _upsert(
        NetworkSettingKeys.remoteHostAddress,
        networkSettings.remoteHostAddress,
        now,
      );
      await _upsert(
        NetworkSettingKeys.remoteHostPort,
        networkSettings.remoteHostPort.toString(),
        now,
      );
      await _upsert(
        NetworkSettingKeys.securityPin,
        networkSettings.securityPin,
        now,
      );
      await AuditRepository(_db).log(
        action: AuditAction.storeDetailsUpdated,
        userId: actingUserId,
        entityType: 'settings',
        details:
            'Station network mode updated to ${networkSettings.mode.name} (Port: ${networkSettings.hostPort})',
      );
    });
  }

  static NetworkSettings _toNetworkSettings(List<Setting> rows) {
    if (rows.isEmpty) return const NetworkSettings();
    final map = {for (final r in rows) r.key: r.value};
    final modeStr = map[NetworkSettingKeys.stationMode];
    final hostPortStr = map[NetworkSettingKeys.hostPort];
    final remoteAddress = map[NetworkSettingKeys.remoteHostAddress] ?? '';
    final remotePortStr = map[NetworkSettingKeys.remoteHostPort];
    final pin = map[NetworkSettingKeys.securityPin] ?? '';

    return NetworkSettings(
      mode: NetworkStationMode.fromString(modeStr),
      hostPort: int.tryParse(hostPortStr ?? '') ?? 4242,
      remoteHostAddress: remoteAddress,
      remoteHostPort: int.tryParse(remotePortStr ?? '') ?? 4242,
      securityPin: pin,
    );
  }

  static PrinterSettings _toPrinterSettings(List<Setting> rows) {
    if (rows.isEmpty) return const PrinterSettings();
    final map = {for (final r in rows) r.key: r.value};
    final url = map[PrinterSettingKeys.selectedPrinterUrl];
    final name = map[PrinterSettingKeys.selectedPrinterName];
    final directStr = map[PrinterSettingKeys.directPrinting];
    return PrinterSettings(
      selectedPrinterUrl: url?.isEmpty ?? true ? null : url,
      selectedPrinterName: name?.isEmpty ?? true ? null : name,
      directPrinting: directStr == null ? true : directStr.toLowerCase() == 'true',
    );
  }

  static AppThemeSettings _toThemeSettings(List<Setting> rows) {
    if (rows.isEmpty) return const AppThemeSettings();
    final map = {for (final r in rows) r.key: r.value};
    return AppThemeSettings(
      themeMode: AppThemeSettings.parseThemeMode(map[ThemeSettingKeys.themeMode]),
      primaryColor: AppThemeSettings.parseColorHex(map[ThemeSettingKeys.themeColor]),
      presetId: map[ThemeSettingKeys.themePreset] ?? 'emerald',
    );
  }

  static StoreInfo _toStoreInfo(List<Setting> rows) {
    if (rows.isEmpty) return kStoreInfo;
    final map = {for (final r in rows) r.key: r.value};
    return StoreInfo(
      name: map[StoreSettingKeys.name]?.trim().isEmpty ?? true
          ? kStoreInfo.name
          : map[StoreSettingKeys.name]!.trim(),
      address: map[StoreSettingKeys.address]?.trim().isEmpty ?? true
          ? kStoreInfo.address
          : map[StoreSettingKeys.address]!.trim(),
      phone: map[StoreSettingKeys.phone]?.trim().isEmpty ?? true
          ? kStoreInfo.phone
          : map[StoreSettingKeys.phone]!.trim(),
    );
  }

  static ReceiptCustomization _toReceiptCustomization(List<Setting> rows) {
    if (rows.isEmpty) return const ReceiptCustomization();
    final map = {for (final r in rows) r.key: r.value};
    const defaults = ReceiptCustomization();

    bool pickBool(String key, bool fallback) {
      final val = map[key];
      if (val == null) return fallback;
      return val.toLowerCase() == 'true';
    }

    String pick(String key, String fallback) {
      return map[key] ?? fallback;
    }

    return ReceiptCustomization(
      showStoreName: pickBool(
        ReceiptSettingKeys.showStoreName,
        defaults.showStoreName,
      ),
      showStoreAddress: pickBool(
        ReceiptSettingKeys.showStoreAddress,
        defaults.showStoreAddress,
      ),
      showStorePhone: pickBool(
        ReceiptSettingKeys.showStorePhone,
        defaults.showStorePhone,
      ),
      headerCustomText: pick(
        ReceiptSettingKeys.headerCustomText,
        defaults.headerCustomText,
      ),
      showCashierName: pickBool(
        ReceiptSettingKeys.showCashierName,
        defaults.showCashierName,
      ),
      showItemPriceMath: pickBool(
        ReceiptSettingKeys.showItemPriceMath,
        defaults.showItemPriceMath,
      ),
      showTax: pickBool(ReceiptSettingKeys.showTax, defaults.showTax),
      showDiscount: pickBool(
        ReceiptSettingKeys.showDiscount,
        defaults.showDiscount,
      ),
      showPaymentBreakdown: pickBool(
        ReceiptSettingKeys.showPaymentBreakdown,
        defaults.showPaymentBreakdown,
      ),
      showChangeDue: pickBool(
        ReceiptSettingKeys.showChangeDue,
        defaults.showChangeDue,
      ),
      footerMessage: pick(
        ReceiptSettingKeys.footerMessage,
        defaults.footerMessage,
      ),
      showBarcode: pickBool(
        ReceiptSettingKeys.showBarcode,
        defaults.showBarcode,
      ),
      showCustomerSignature: pickBool(
        ReceiptSettingKeys.showCustomerSignature,
        defaults.showCustomerSignature,
      ),
      paperWidth: pick(
        ReceiptSettingKeys.paperWidth,
        defaults.paperWidth,
      ),
      sideMargin: double.tryParse(
            pick(ReceiptSettingKeys.sideMargin, defaults.sideMargin.toString()),
          ) ??
          defaults.sideMargin,
      bottomFeedSpace: double.tryParse(
            pick(
              ReceiptSettingKeys.bottomFeedSpace,
              defaults.bottomFeedSpace.toString(),
            ),
          ) ??
          defaults.bottomFeedSpace,
    );
  }
}
