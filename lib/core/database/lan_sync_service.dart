import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/core/database/sync_schema.dart';
import 'package:instrument_pos/core/database/workstation_config.dart';
import 'package:instrument_pos/core/security/sync_auth.dart';

/// Delta sync between a client terminal and the host station.
///
/// One cycle = handshake, outbox flush, pull:
///  * `/api/hello` checks the host schema and cursor;
///  * `/api/outbox` ships every row this station still marks `dirty`,
///    parent tables first, and stamps the host's revision on acceptance;
///  * `/api/changes` applies host rows this station has not seen yet —
///    rows with local pending edits are left alone so the push wins the
///    conflict check instead of being silently overwritten.
///
/// The host may be a laptop that leaves and returns: nothing here assumes a
/// connection survives between cycles, and every request is safe to retry.
class LanSyncService {
  LanSyncService(this._localDb) {
    instance = this;
  }

  static LanSyncService? instance;

  /// Globally trigger immediate sync from anywhere in the app (e.g. checkout).
  static void triggerSync() {
    unawaited(instance?.syncNow());
  }

  final AppDatabase _localDb;

  late final Map<String, TableInfo<Table, DataClass>> _infos =
      syncTableInfos(_localDb);

  Timer? _heartbeatTimer;
  Timer? _cycleTimer;
  bool _isStarted = false;
  bool _isSyncing = false;
  Duration _interval = const Duration(seconds: 5);

  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> pendingSyncCountNotifier = ValueNotifier<int>(0);

  /// Last handshake/push/pull failure, for the sync status UI.
  final ValueNotifier<String> statusNotifier = ValueNotifier<String>('Idle');

  static const _heartbeatInterval = Duration(seconds: 10);
  static const _httpTimeout = Duration(seconds: 8);
  static const _minInterval = Duration(seconds: 5);
  static const _maxInterval = Duration(seconds: 60);
  static const _pageSize = 500;
  static const _opsPerBatch = 200;
  static const _rowsPerTablePerCycle = 100;

  WorkstationConfig get _config => WorkstationConfig.current;

  bool get _canSync {
    final config = _config;
    return config.isClient && config.hostAddress.isNotEmpty;
  }

  void start() {
    if (_isStarted) return;
    _isStarted = true;
    if (!_canSync) {
      isOnlineNotifier.value = true;
      return;
    }
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => unawaited(_sendHeartbeat()),
    );
    unawaited(_sendHeartbeat());
    _scheduleCycle();
    unawaited(syncNow());
  }

  void stop() {
    if (!_isStarted) return;
    _isStarted = false;
    _heartbeatTimer?.cancel();
    _cycleTimer?.cancel();
    _heartbeatTimer = null;
    _cycleTimer = null;
    _unregister();
    isOnlineNotifier.value = false;
  }

  /// Re-reads the workstation mode: called after the user switches between
  /// host / client / standalone at runtime.
  Future<void> restart() async {
    stop();
    start();
    if (_canSync) await syncNow();
  }

  /// Runs one cycle right now (sale completed, catalog edit, …).
  Future<void> syncNow() async {
    if (!_canSync || _isSyncing) return;
    await _runCycle();
  }

  // ── Cycle ────────────────────────────────────────────────────────────────

  Future<void> _runCycle() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final hello = await _hello();
      if (hello == null) return;

      if (hello['forceFullSync'] == true) {
        // The host database was rebuilt under us: start over.
        await WorkstationConfig.saveLastRev(0);
      }

      final pushed = await _flushOutbox();
      final pulled = await _pullChanges();
      await _refreshPendingCount();
      if (pushed && pulled) _succeed('Synced');
    } finally {
      _isSyncing = false;
      if (_isStarted) _scheduleCycle();
    }
  }

  void _scheduleCycle() {
    _cycleTimer?.cancel();
    if (!_isStarted) return;
    _cycleTimer = Timer(_interval, () {
      unawaited(_runCycle());
    });
  }

  void _succeed(String message) {
    _interval = _minInterval;
    isOnlineNotifier.value = true;
    statusNotifier.value = message;
  }

  void _fail(String message) {
    // Back off while the host is away so a laptop that left the shop does
    // not get hammered; reset on the first success.
    final doubled = _interval * 2;
    _interval = doubled > _maxInterval ? _maxInterval : doubled;
    isOnlineNotifier.value = false;
    statusNotifier.value = message;
    debugPrint('[LanSyncService] $message');
  }

  // ── Handshake ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _hello() async {
    final result = await _post('/api/hello', {
      'stationId': _config.stationId,
      'schemaVersion': AppDatabase.currentSchemaVersion,
      'lastRev': _config.lastRev,
    });
    final body = result.body;
    if (result.statusCode != HttpStatus.ok || body == null) {
      _fail(_describeFailure(result));
      return null;
    }
    if (body['ok'] != true) {
      _fail(_describeFailure(result));
      return null;
    }
    return body;
  }

  String _describeFailure(_ApiResult result) {
    final error = result.body?['error'] as String?;
    switch (error) {
      case 'pin_required':
        return 'Host has no security PIN set — sync is disabled.';
      case 'unauthorized':
        return 'Sync PIN rejected by the host.';
      case 'schema_mismatch':
        return 'Host runs a different app version — update this terminal.';
    }
    if (result.statusCode == 0) {
      return 'Host unreachable at ${_config.hostAddress}:${_config.hostPort}.';
    }
    return 'Host responded with HTTP ${result.statusCode}.';
  }

  // ── Push ─────────────────────────────────────────────────────────────────

  Future<bool> _flushOutbox() async {
    final ops = await _collectOps();
    if (ops.isEmpty) return true;

    for (var start = 0; start < ops.length; start += _opsPerBatch) {
      final batch = ops.sublist(
        start,
        start + _opsPerBatch > ops.length ? ops.length : start + _opsPerBatch,
      );
      final result = await _post('/api/outbox', {'ops': batch});
      if (result.statusCode != HttpStatus.ok || result.body?['ok'] != true) {
        _fail(_describeFailure(result));
        return false;
      }
      final results = (result.body!['results'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      await _applyResults(batch, results);
    }
    return true;
  }

  /// Every row this station still owes the host, parent tables first.
  Future<List<Map<String, dynamic>>> _collectOps() async {
    final ops = <Map<String, dynamic>>[];
    for (final spec in syncTables) {
      final info = _infos[spec.table];
      if (info == null || spec.fromJson == null) continue;
      final rows = await selectSyncRows(
        _localDb,
        info,
        where: 'dirty = 1',
        limit: _rowsPerTablePerCycle,
      );
      for (final row in rows) {
        final payload = row.toJson();
        // Machine-local settings (printer.*, theme_*) are never shared.
        if (spec.table == 'settings' &&
            !isSharedSettingKey(payload['key'] as String? ?? '')) {
          continue;
        }
        ops.add({
          'opId': '${spec.table}|${payload[syncPrimaryKey(spec.table)]}',
          'table': spec.table,
          'kind': spec.kind.name,
          'baseRev': payload['rev'],
          'payload': payload,
        });
      }
    }
    return ops;
  }

  Future<void> _applyResults(
    List<Map<String, dynamic>> ops,
    List<Map<String, dynamic>> results,
  ) async {
    final byId = {for (final r in results) r['opId'] as String: r};
    for (final op in ops) {
      final result = byId[op['opId'] as String];
      if (result == null) continue;
      final table = op['table'] as String;
      final entityId = op['payload'][syncPrimaryKey(table)] as String;
      final status = result['status'] as String? ?? '';

      switch (status) {
        case 'applied':
        case 'duplicate':
          await _ack(table, entityId, result['rev'] as int? ?? 0);
          await _clearFailure(table, entityId);
        case 'ignored':
          await _ack(table, entityId, result['rev'] as int? ?? 0);
        case 'conflict':
          await _resolveConflict(op, result);
        default:
          await _recordFailure(
            op,
            result['message'] as String? ?? 'Rejected by host',
          );
      }
    }
  }

  /// Host accepted the row: store its revision and stop pushing it.
  Future<void> _ack(String table, String entityId, int rev) async {
    final pk = syncPrimaryKey(table);
    final extra = table == 'sales' ? ', is_synced = 1' : '';
    await _localDb.customUpdate(
      'UPDATE "$table" SET rev = ?, dirty = 0$extra WHERE "$pk" = ?',
      variables: [Variable.withInt(rev), Variable.withString(entityId)],
      updates: {_infos[table]!},
    );
  }

  Future<void> _resolveConflict(
    Map<String, dynamic> op,
    Map<String, dynamic> result,
  ) async {
    final table = op['table'] as String;
    final entityId = op['payload'][syncPrimaryKey(table)] as String;
    final code = result['code'] as String? ?? '';

    if (code == 'stale') {
      // Host row moved on while we edited: the host is the source of truth.
      await writeSyncRow(
        _localDb,
        table: table,
        info: _infos[table]!,
        row: syncSpecFor(table)!.fromJson!(
          result['row'] as Map<String, dynamic>,
        )!,
        entityId: entityId,
        rev: result['rev'] as int? ?? 0,
        dirty: false,
        replaceOnConflict: true,
      );
      await _clearFailure(table, entityId);
      debugPrint('[LanSyncService] $table/$entityId resolved: host version kept');
      return;
    }

    if (code == 'unique') {
      final column = result['column'] as String?;
      final renamed = await _freeUniqueValue(table, entityId, column);
      if (renamed) {
        await _clearFailure(table, entityId);
        return;
      }
    }
    await _recordFailure(op, 'Conflict on $table/$entityId');
  }

  /// Frees a colliding SKU/name by tagging it with this station's code so
  /// the row can be pushed on the next cycle instead of looping forever.
  /// Returns false when the column must not be rewritten (usernames).
  Future<bool> _freeUniqueValue(
    String table,
    String entityId,
    String? column,
  ) async {
    const renameable = {
      'products': 'sku',
      'categories': 'name',
      'brands': 'name',
      'import_batches': 'batch_number',
    };
    final expected = renameable[table];
    if (column == null || expected != column) return false;

    final code = _config.stationCode;
    if (code.isEmpty) return false;
    final pk = syncPrimaryKey(table);
    final rows = await _localDb.customSelect(
      'SELECT "$column" AS value FROM "$table" WHERE "$pk" = ?',
      variables: [Variable.withString(entityId)],
    ).get();
    if (rows.isEmpty) return false;
    final current = rows.first.read<String?>('value') ?? '';
    final suffix = '-$code';
    if (current.endsWith(suffix)) return false;
    await _localDb.customUpdate(
      'UPDATE "$table" SET "$column" = ? WHERE "$pk" = ?',
      variables: [
        Variable.withString('$current$suffix'),
        Variable.withString(entityId),
      ],
      updates: {_infos[table]!},
    );
    debugPrint(
      '[LanSyncService] Renamed $table.$column "$current" -> "$current$suffix"',
    );
    return true;
  }

  Future<void> _recordFailure(Map<String, dynamic> op, String message) async {
    final table = op['table'] as String;
    final entityId = op['payload'][syncPrimaryKey(table)] as String;
    final id = '$table|$entityId';
    final existing = await (_localDb.select(_localDb.syncQueue)
          ..where((q) => q.id.equals(id)))
        .getSingleOrNull();
    await _localDb.into(_localDb.syncQueue).insertOnConflictUpdate(
          SyncQueueEntry(
            id: id,
            kind: op['kind'] as String? ?? 'tx',
            targetTable: table,
            entityId: entityId,
            baseRev: op['baseRev'] as int? ?? 0,
            payload: jsonEncode(op['payload']),
            retryCount: (existing?.retryCount ?? 0) + 1,
            status: 'PENDING',
            lastError: message,
            createdAt: existing?.createdAt ?? DateTime.now(),
          ),
        );
    debugPrint('[LanSyncService] Push failed for $id: $message');
  }

  Future<void> _clearFailure(String table, String entityId) async {
    await (_localDb.delete(_localDb.syncQueue)
          ..where((q) => q.id.equals('$table|$entityId')))
        .go();
  }

  // ── Pull ─────────────────────────────────────────────────────────────────

  Future<bool> _pullChanges() async {
    for (var page = 0; page < 500; page++) {
      final since = WorkstationConfig.current.lastRev;
      final result = await _get('/api/changes', query: {
        'since': '$since',
        'limit': '$_pageSize',
      });
      if (result.statusCode != HttpStatus.ok || result.body?['ok'] != true) {
        _fail(_describeFailure(result));
        return false;
      }
      final body = result.body!;
      for (final change in (body['changes'] as List<dynamic>? ?? [])) {
        await _applyChange(change as Map<String, dynamic>);
      }
      await WorkstationConfig.saveLastRev(body['lastRev'] as int? ?? since);
      if (body['hasMore'] != true) return true;
    }
    return true;
  }

  Future<void> _applyChange(Map<String, dynamic> change) async {
    final table = change['table'] as String;
    final spec = syncSpecFor(table);
    final info = _infos[table];
    final payload = change['row'] as Map<String, dynamic>?;
    if (spec?.fromJson == null || info == null || payload == null) return;

    final entityId = payload[syncPrimaryKey(table)] as String?;
    if (entityId == null || entityId.isEmpty) return;
    if (table == 'settings' &&
        !isSharedSettingKey(payload['key'] as String? ?? '')) {
      return;
    }

    final meta = await readSyncRowMeta(_localDb, table, entityId);
    // A catalog row with local pending edits must reach the host first —
    // pushing it is what surfaces the conflict honestly.
    if (meta != null && meta.dirty && spec!.isCatalog) return;

    await writeSyncRow(
      _localDb,
      table: table,
      info: info,
      row: spec!.fromJson!(payload)!,
      entityId: entityId,
      rev: change['rev'] as int? ?? 0,
      dirty: false,
      replaceOnConflict: true,
    );
  }

  Future<void> _refreshPendingCount() async {
    if (!_canSync) {
      pendingSyncCountNotifier.value = 0;
      return;
    }
    var total = 0;
    for (final spec in syncTables) {
      if (spec.table == 'settings') continue;
      final rows = await _localDb.customSelect(
        'SELECT COUNT(*) AS c FROM "${spec.table}" WHERE dirty = 1',
      ).get();
      total += rows.first.read<int>('c');
    }
    final settings = await _localDb.customSelect(
      'SELECT COUNT(*) AS c FROM settings WHERE dirty = 1 AND ('
      "key LIKE 'store.%' OR key LIKE 'receipt.%' "
      "OR key = 'inventory.lowStockThreshold')",
    ).get();
    total += settings.first.read<int>('c');
    pendingSyncCountNotifier.value = total;
  }

  // ── Presence ─────────────────────────────────────────────────────────────

  Future<void> _sendHeartbeat() async {
    if (!_canSync || _config.stationId.isEmpty) return;
    try {
      final result = await _post(
        '/api/heartbeat',
        {
          'id': _config.stationId,
          'stationName': _config.stationName.isNotEmpty
              ? _config.stationName
              : Platform.localHostname,
        },
        authenticated: false,
      );
      isOnlineNotifier.value =
          result.statusCode == HttpStatus.ok && result.body?['ok'] == true;
    } catch (e) {
      isOnlineNotifier.value = false;
      debugPrint('[LanSyncService] Heartbeat failed: $e');
    }
  }

  Future<void> _unregister() async {
    if (!_canSync || _config.stationId.isEmpty) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final uri = Uri.http(
        '${_config.hostAddress}:${_config.hostPort}',
        '/api/heartbeat/${_config.stationId}',
      );
      final request = await client
          .deleteUrl(uri)
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 2));
      await response.drain<void>();
    } catch (_) {
      // Best-effort — the host expires us after 45s anyway.
    } finally {
      client.close();
    }
  }

  // ── HTTP ─────────────────────────────────────────────────────────────────

  Future<_ApiResult> _get(String path, {Map<String, String>? query}) async {
    final config = _config;
    if (config.hostAddress.isEmpty) {
      return const _ApiResult(0, null);
    }
    final client = HttpClient()..connectionTimeout = _httpTimeout;
    try {
      final uri = Uri.http('${config.hostAddress}:${config.hostPort}', path, query);
      final request = await client.getUrl(uri).timeout(_httpTimeout);
      _applyAuth(request, config);
      final response = await request.close().timeout(_httpTimeout);
      return await _readResult(response);
    } catch (_) {
      return const _ApiResult(0, null);
    } finally {
      client.close();
    }
  }

  Future<_ApiResult> _post(
    String path,
    Object body, {
    bool authenticated = true,
  }) async {
    final config = _config;
    if (config.hostAddress.isEmpty) {
      return const _ApiResult(0, null);
    }
    final client = HttpClient()..connectionTimeout = _httpTimeout;
    try {
      final uri = Uri.http('${config.hostAddress}:${config.hostPort}', path);
      final request = await client.postUrl(uri).timeout(_httpTimeout);
      _applyAuth(request, config, enabled: authenticated);
      final encoded = jsonEncode(body);
      request.headers.contentType = ContentType.json;
      request.headers.contentLength = utf8.encode(encoded).length;
      request.write(encoded);
      final response = await request.close().timeout(_httpTimeout);
      return await _readResult(response);
    } catch (_) {
      return const _ApiResult(0, null);
    } finally {
      client.close();
    }
  }

  void _applyAuth(
    HttpClientRequest request,
    WorkstationConfig config, {
    bool enabled = true,
  }) {
    if (!enabled) return;
    request.headers.set('X-Station-Id', config.stationId);
    request.headers.set(
      'X-Auth-Token',
      syncToken(pin: config.securityPin, stationId: config.stationId),
    );
  }

  Future<_ApiResult> _readResult(HttpClientResponse response) async {
    final raw = await response.transform(utf8.decoder).join();
    Map<String, dynamic>? body;
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        body = null;
      }
    }
    return _ApiResult(response.statusCode, body);
  }
}

class _ApiResult {
  const _ApiResult(this.statusCode, this.body);

  final int statusCode;
  final Map<String, dynamic>? body;
}

/// Singleton provider for the LAN synchronization service.
final lanSyncServiceProvider = Provider<LanSyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final service = LanSyncService(db);
  service.start();
  ref.onDispose(service.stop);
  return service;
});
