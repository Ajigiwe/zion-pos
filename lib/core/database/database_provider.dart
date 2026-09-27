import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';

/// Opens the fast local SQLite database for offline-first operation.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
