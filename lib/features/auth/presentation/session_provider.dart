import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/features/auth/data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return DriftAuthRepository(ref.watch(databaseProvider));
});

/// The user signed in on this device. The app is offline-first, so login is
/// verified against the local users table — no network round-trip (§33).
class Session extends Notifier<User?> {
  @override
  User? build() => null;

  /// Returns an error message, or null when the login succeeded.
  Future<String?> signIn({
    required String username,
    required String password,
  }) async {
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .authenticate(username.trim(), password);
      state = user;
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'An unexpected error occurred. Please try again.';
    }
  }

  void signOut() => state = null;
}

final sessionProvider = NotifierProvider<Session, User?>(Session.new);

/// Convenience read-only view of the active user.
final currentUserProvider = Provider<User?>(
  (ref) => ref.watch(sessionProvider),
);
