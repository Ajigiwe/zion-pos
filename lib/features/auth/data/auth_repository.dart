import 'package:drift/drift.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/lan_database_client.dart';
import 'package:instrument_pos/core/database/workstation_config.dart';
import 'package:instrument_pos/core/security/passwords.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';
import 'package:uuid/uuid.dart';

/// Wrong credentials, a disabled account, or an invalid user operation.
class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class AuthRepository {
  /// Returns the matching active user or throws [AuthException].
  Future<User> authenticate(String username, String password);

  /// Live list of all users for the management screen.
  Stream<List<User>> watchUsers();

  /// Creates an account with a hashed password. Throws [AuthException] when
  /// the username is taken.
  Future<User> createUser({
    required String username,
    required String displayName,
    required String role,
    required String password,
  });

  Future<void> setActive(
    String userId, {
    required bool active,
    String? actingUserId,
  });

  /// Number of active OWNER accounts (used to keep the last owner enabled).
  Future<int> countActiveOwners();

  /// Changes the user's own password after verifying the current one.
  /// Throws [AuthException] on a wrong current password or a too-short new one.
  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  });
}

class DriftAuthRepository implements AuthRepository {
  DriftAuthRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  @override
  Future<User> authenticate(String username, String password) async {
    final normalized = username.trim().toLowerCase();
    final config = WorkstationConfig.current;

    // Step 1: Always check local SQLite first (works offline, instant).
    // On Host/Standalone this is the master DB.
    // On Client, LanSyncService keeps this cache updated from the Host.
    final row = await (_db.select(
      _db.users,
    )..where((u) => u.username.lower().equals(normalized))).getSingleOrNull();

    if (row != null) {
      if (!row.isActive || !verifyPassword(password, row.passwordHash)) {
        await AuditRepository(_db).log(
          action: AuditAction.loginFailed,
          entityType: 'user',
          entityId: normalized,
        );
        throw AuthException('Invalid username or password.');
      }
      await AuditRepository(_db).log(
        action: AuditAction.login,
        userId: row.id,
        entityType: 'user',
        entityId: row.id,
        details: '$normalized (${config.isClient ? "Client" : config.isHost ? "Host" : "Standalone"})',
      );
      return row;
    }

    // Step 2: User not in local cache — if we're a client station,
    // authenticate directly against the Host via a lightweight HTTP POST.
    // This handles the case where the app just started and sync hasn't run yet.
    if (config.isClient && config.hostAddress.isNotEmpty) {
      final userData = await LanDatabaseClient.authenticateOnHost(
        host: config.hostAddress,
        port: config.hostPort,
        username: normalized,
        password: password,
      );

      if (userData != null) {
        // Cache the verified user into local DB for future offline logins
        final cachedUser = User(
          id: userData['id'] as String,
          username: userData['username'] as String,
          displayName: userData['displayName'] as String,
          passwordHash: userData['passwordHash'] as String,
          role: userData['role'] as String,
          isActive: userData['isActive'] as bool,
          createdAt: DateTime.parse(userData['createdAt'] as String),
          rev: userData['rev'] as int? ?? 1,
          dirty: false,
        );

        final existingUser = await (_db.select(_db.users)
              ..where((u) =>
                  u.id.equals(cachedUser.id) |
                  u.username.equals(cachedUser.username)))
            .getSingleOrNull();

        if (existingUser != null) {
          await (_db.update(_db.users)
                ..where((u) => u.id.equals(existingUser.id)))
              .write(
            UsersCompanion(
              id: Value(cachedUser.id),
              username: Value(cachedUser.username),
              displayName: Value(cachedUser.displayName),
              passwordHash: Value(cachedUser.passwordHash),
              role: Value(cachedUser.role),
              isActive: Value(cachedUser.isActive),
              createdAt: Value(cachedUser.createdAt),
              rev: Value(cachedUser.rev),
              dirty: const Value(false),
            ),
          );
        } else {
          await _db.into(_db.users).insert(
            UsersCompanion.insert(
              id: cachedUser.id,
              username: cachedUser.username,
              displayName: cachedUser.displayName,
              passwordHash: cachedUser.passwordHash,
              role: cachedUser.role,
              isActive: Value(cachedUser.isActive),
              createdAt: Value(cachedUser.createdAt),
              rev: Value(cachedUser.rev),
              dirty: const Value(false),
            ),
          );
        }
        await AuditRepository(_db).log(
          action: AuditAction.login,
          userId: cachedUser.id,
          entityType: 'user',
          entityId: cachedUser.id,
          details: '$normalized (Client → Host REST Auth)',
        );
        return cachedUser;
      }

      // Host rejected the credentials or is unreachable
      await AuditRepository(_db).log(
        action: AuditAction.loginFailed,
        entityType: 'user',
        entityId: normalized,
      );
      throw AuthException(
        'Invalid username or password. '
        'If this is your first login on this terminal, ensure the Host PC is running.',
      );
    }

    // Step 3: Standalone/Host — user simply doesn't exist
    await AuditRepository(_db).log(
      action: AuditAction.loginFailed,
      entityType: 'user',
      entityId: normalized,
    );
    throw AuthException('Invalid username or password.');
  }

  @override
  Stream<List<User>> watchUsers() {
    final query = _db.select(_db.users)
      ..orderBy([(u) => OrderingTerm.asc(u.username)]);
    return query.watch();
  }

  @override
  Future<User> createUser({
    required String username,
    required String displayName,
    required String role,
    required String password,
  }) async {
    final normalized = username.trim().toLowerCase();
    final existing = await (_db.select(
      _db.users,
    )..where((u) => u.username.lower().equals(normalized))).getSingleOrNull();
    if (existing != null) {
      throw AuthException('That username is already taken.');
    }
    final id = _uuid.v4();
    final row = User(
      id: id,
      username: normalized,
      displayName: displayName.trim(),
      passwordHash: hashPassword(password),
      role: role.toUpperCase(),
      isActive: true,
      createdAt: DateTime.now(),
      rev: 1,
      dirty: true,
    );
    await _db
        .into(_db.users)
        .insert(
          UsersCompanion(
            id: Value(row.id),
            username: Value(row.username),
            displayName: Value(row.displayName),
            passwordHash: Value(row.passwordHash),
            role: Value(row.role),
            isActive: Value(row.isActive),
            createdAt: Value(row.createdAt),
          ),
        );
    await AuditRepository(_db).log(
      action: AuditAction.userCreate,
      userId: row.id,
      entityType: 'user',
      entityId: row.id,
      details: '${row.displayName} (@${row.username}) as ${row.role}',
    );
    return row;
  }

  @override
  Future<void> setActive(
    String userId, {
    required bool active,
    String? actingUserId,
  }) async {
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(isActive: Value(active)),
    );
    await AuditRepository(_db).log(
      action: active ? AuditAction.userActivate : AuditAction.userDeactivate,
      userId: actingUserId,
      entityType: 'user',
      entityId: userId,
      details: active ? 'Activated' : 'Deactivated',
    );
  }

  @override
  Future<int> countActiveOwners() async {
    final query = _db.selectOnly(_db.users)
      ..addColumns([_db.users.id.count()])
      ..where(_db.users.role.equals('OWNER') & _db.users.isActive.equals(true));
    final row = await query.getSingle();
    return row.read(_db.users.id.count()) ?? 0;
  }

  @override
  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final row = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (row == null) {
      throw AuthException('User not found.');
    }
    if (!verifyPassword(currentPassword, row.passwordHash)) {
      throw AuthException('Current password is incorrect.');
    }
    if (newPassword.length < 6) {
      throw AuthException('The new password must be at least 6 characters.');
    }
    await (_db.update(_db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(passwordHash: Value(hashPassword(newPassword))),
    );
    await AuditRepository(_db).log(
      action: AuditAction.passwordChanged,
      userId: userId,
      entityType: 'user',
      entityId: userId,
    );
  }
}
