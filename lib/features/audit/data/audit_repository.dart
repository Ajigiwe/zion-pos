import 'package:drift/drift.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

/// Audit actions, mirroring design doc §32.
abstract final class AuditAction {
  static const login = 'LOGIN';
  static const loginFailed = 'LOGIN_FAILED';
  static const sale = 'SALE';
  static const refund = 'REFUND';
  static const exchange = 'EXCHANGE';
  static const stockAdjustment = 'STOCK_ADJUSTMENT';
  static const openingStock = 'OPENING_STOCK';
  static const importBatch = 'IMPORT';
  static const userCreate = 'USER_CREATE';
  static const userDeactivate = 'USER_DEACTIVATED';
  static const userActivate = 'USER_ACTIVATED';
  static const passwordChanged = 'PASSWORD_CHANGED';
  static const storeDetailsUpdated = 'STORE_DETAILS_UPDATED';
  static const backup = 'BACKUP';
  static const restore = 'RESTORE';
}

/// Appends audit entries to the same database the operations write to, so a
/// transaction rolls them back together with the operation itself (§32, §39).
class AuditEntry {
  const AuditEntry({required this.log, this.userName});

  final AuditLog log;
  final String? userName;
}

class AuditRepository {
  AuditRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<void> log({
    required String action,
    String? userId,
    String? entityType,
    String? entityId,
    String? details,
  }) {
    return _db
        .into(_db.auditLogs)
        .insert(
          AuditLogsCompanion(
            id: Value(_uuid.v4()),
            userId: Value<String?>(userId),
            action: Value(action),
            entityType: Value<String?>(entityType),
            entityId: Value<String?>(entityId),
            details: Value<String?>(details),
            deviceId: const Value<String?>(null),
            createdAt: Value(DateTime.now()),
          ),
        );
  }

  /// Newest entries first, with the acting user's name resolved for display.
  Stream<List<AuditEntry>> watchRecent({int limit = 200}) {
    final query =
        _db.select(_db.auditLogs).join([
            leftOuterJoin(
              _db.users,
              _db.users.id.equalsExp(_db.auditLogs.userId),
            ),
          ])
          ..orderBy([OrderingTerm.desc(_db.auditLogs.createdAt)])
          ..limit(limit);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          AuditEntry(
            log: row.readTable(_db.auditLogs),
            userName: row.readTableOrNull(_db.users)?.username,
          ),
      ],
    );
  }
}
