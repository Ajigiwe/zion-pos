/// Store identity shown in the app branding and printed on every receipt.
/// Edit this single source of truth to rebrand for a different shop.
class StoreInfo {
  const StoreInfo({
    required this.name,
    required this.address,
    required this.phone,
  });

  final String name;
  final String address;
  final String phone;

  @override
  bool operator ==(Object other) =>
      other is StoreInfo &&
      other.name == name &&
      other.address == address &&
      other.phone == phone;

  @override
  int get hashCode => Object.hash(name, address, phone);
}

const kStoreInfo = StoreInfo(
  name: 'Zion Musical Centre',
  address: 'Market Circle - Tarkwa',
  phone: '054 171 7773 / 0275439830',
);

/// Default low-stock alert threshold used when a product has no reorder level
/// of its own. Editable in Settings.
const kDefaultLowStockThreshold = 5.0;

/// Splits a contact field into individual phone lines. Handles several
/// numbers separated by '/' (the format the store profile uses); a single
/// number comes back untouched.
List<String> phoneLines(String raw) {
  return [
    for (final part in raw.split('/'))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

/// Keys under which each [StoreInfo] field lives in the `settings` table.
abstract final class StoreSettingKeys {
  static const name = 'store.name';
  static const address = 'store.address';
  static const phone = 'store.phone';

  /// Global low-stock alert threshold (a number stored as text).
  static const lowStockThreshold = 'inventory.lowStockThreshold';
}
