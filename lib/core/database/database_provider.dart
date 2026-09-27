import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';

/// Opens the fast local SQLite database for offline-first operation.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  // `.ignore()`: the restore path may already have closed this database.
  ref.onDispose(() => db.close().ignore());
  return db;
});
