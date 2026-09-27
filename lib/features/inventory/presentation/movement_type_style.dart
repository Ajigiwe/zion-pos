import 'package:flutter/material.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/inventory/domain/movement_type_meta.dart';

extension MovementTypeStyle on MovementType {
  IconData get icon => switch (this) {
    MovementType.openingStock => Icons.playlist_add,
    MovementType.purchase => Icons.add_shopping_cart,
    MovementType.bulkImport => Icons.upload_file,
    MovementType.sale => Icons.point_of_sale,
    MovementType.refund => Icons.replay,
    MovementType.exchangeReturn => Icons.swap_horiz,
    MovementType.exchangeSale => Icons.swap_horiz,
    MovementType.damage => Icons.report_problem_outlined,
    MovementType.adjustment => Icons.tune,
    MovementType.transferIn => Icons.south_west,
    MovementType.transferOut => Icons.north_east,
  };

  Color color(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return isIncrease ? scheme.primary : scheme.error;
  }
}

/// Colors a signed ledger quantity: gains green, losses red.
Color quantityColor(BuildContext context, double quantity) => quantity >= 0
    ? const Color(0xFF2E7D32)
    : Theme.of(context).colorScheme.error;

String signedQuantity(double quantity) =>
    quantity >= 0 ? '+${_trim(quantity)}' : _trim(quantity).toString();

String _trim(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();
