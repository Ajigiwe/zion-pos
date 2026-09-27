import 'package:instrument_pos/core/database/tables.dart';

/// Human-readable labels for ledger movement types (§13).
extension MovementTypeLabel on MovementType {
  String get label => switch (this) {
    MovementType.openingStock => 'Opening stock',
    MovementType.purchase => 'Purchase',
    MovementType.bulkImport => 'Bulk import',
    MovementType.sale => 'Sale',
    MovementType.refund => 'Refund',
    MovementType.exchangeReturn => 'Exchange return',
    MovementType.exchangeSale => 'Exchange sale',
    MovementType.damage => 'Damage',
    MovementType.adjustment => 'Adjustment',
    MovementType.transferIn => 'Transfer in',
    MovementType.transferOut => 'Transfer out',
  };

  /// Whether this type represents stock arriving at the shop.
  bool get isIncrease => switch (this) {
    MovementType.openingStock ||
    MovementType.purchase ||
    MovementType.bulkImport ||
    MovementType.refund ||
    MovementType.exchangeReturn ||
    MovementType.transferIn => true,
    _ => false,
  };
}

/// The ledger movement types that can be recorded manually from the UI.
enum ManualMovementAction { add, damage, adjust }
