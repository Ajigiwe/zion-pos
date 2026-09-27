import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';

/// Live list of all users for the management screen.
final usersProvider = StreamProvider<List<User>>((ref) {
  return ref.watch(authRepositoryProvider).watchUsers();
});
