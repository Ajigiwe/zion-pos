import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/sync_schema.dart';
import 'package:instrument_pos/core/security/passwords.dart';
import 'package:instrument_pos/core/security/sync_auth.dart';

/// Represents an active secondary POS terminal tracked via HTTP heartbeats.
class ConnectedClientSession {
  ConnectedClientSession({
    required this.id,
    required this.remoteIp,
    required this.stationName,
    required this.connectedAt,
  }) : lastHeartbeat = DateTime.now();

  final String id;
  final String remoteIp;
  final String stationName;
  final DateTime connectedAt;
  DateTime lastHeartbeat;

  String get connectedDurationString {
    final diff = DateTime.now().difference(connectedAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ${diff.inMinutes % 60}m ago';
  }
}

/// Host station HTTP API.
///
/// The protocol is a three-step delta sync (`/api/hello` → `/api/outbox` →
/// `/api/changes`) instead of the old full-state dump, so a terminal can work
/// against a host that restarts, disappears mid-shift or is the shop owner's
/// laptop. Presence stays on unauthenticated heartbeats; every endpoint that
/// touches rows requires a token derived from the pairing PIN.
class LanDatabaseServer {
  LanDatabaseServer(this._db);

  final AppDatabase _db;
  HttpServer? _server;
  String? _securityPin;

  late final Map<String, TableInfo<Table, DataClass>> _infos =
      syncTableInfos(_db);

  // Heartbeat-based presence: stationId -> session
  final Map<String, ConnectedClientSession> _clients = {};
  Timer? _expiryTimer;

  static const _heartbeatTimeout = Duration(seconds: 45);

  final ValueNotifier<int> activeClientsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<List<ConnectedClientSession>> connectedClientsNotifier =
      ValueNotifier<List<ConnectedClientSession>>([]);
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier<bool>(false);

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 4242;

  /// Starts the LAN server on the given [port].
  Future<void> start({int port = 4242, String? securityPin}) async {
    if (_server != null) return;
    _securityPin = securityPin;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      isRunningNotifier.value = true;
      debugPrint('[LanDatabaseServer] Started on port ${_server!.port}');

      _expiryTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _expireStaleClients(),
      );

      _server!.listen(
        (HttpRequest request) => _handleRequest(request),
        onError: (err) {
          debugPrint('[LanDatabaseServer] HTTP Server error: $err');
        },
      );
    } catch (e) {
      debugPrint('[LanDatabaseServer] Failed to start server: $e');
      isRunningNotifier.value = false;
      rethrow;
    }
  }

  void _expireStaleClients() {
    final now = DateTime.now();
    final stale = _clients.entries
        .where((e) => now.difference(e.value.lastHeartbeat) > _heartbeatTimeout)
        .map((e) => e.key)
        .toList();
    if (stale.isEmpty) return;
    for (final id in stale) {
      final session = _clients.remove(id);
      debugPrint('[LanDatabaseServer] Client timed out: ${session?.stationName}');
    }
    _notifyClients();
  }

  void _notifyClients() {
    final list = _clients.values.toList();
    connectedClientsNotifier.value = list;
    activeClientsNotifier.value = list.length;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    request.response.headers
      ..add('Access-Control-Allow-Origin', '*')
      ..add(
        'Access-Control-Allow-Methods',
        'GET, POST, DELETE, OPTIONS',
      )
      ..add(
        'Access-Control-Allow-Headers',
        'Origin, Content-Type, X-Auth-Token, X-Station-Name, X-Station-Id',
      );

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    // --- /status ---
    if (path == '/status' || path == '/api/status') {
      _writeJson(request, {
        'status': 'online',
        'stationMode': 'host',
        'activeClients': _clients.length,
        'schemaVersion': AppDatabase.currentSchemaVersion,
        'requiresPin': _securityPin != null && _securityPin!.isNotEmpty,
        'timestamp': DateTime.now().toIso8601String(),
      });
      return;
    }

    // --- /auth (POST) ---
    if (path == '/auth' && request.method == 'POST') {
      await _handleAuth(request);
      return;
    }

    // --- /api/heartbeat (POST) — client registers/renews presence ---
    if (path == '/api/heartbeat' && request.method == 'POST') {
      await _handleHeartbeat(request);
      return;
    }

    // --- /api/heartbeat/:id (DELETE) — client gracefully unregisters ---
    if (path.startsWith('/api/heartbeat/') && request.method == 'DELETE') {
      final id = path.replaceFirst('/api/heartbeat/', '');
      if (_clients.containsKey(id)) {
        final session = _clients.remove(id);
        _notifyClients();
        debugPrint(
          '[LanDatabaseServer] Client disconnected gracefully: '
          '${session?.stationName}',
        );
      }
      _writeJson(request, {'ok': true});
      return;
    }

    // --- /api/hello (POST) — schema + cursor handshake before syncing ---
    if (path == '/api/hello' && request.method == 'POST') {
      await _withSyncAuth(request, _handleHello);
      return;
    }

    // --- /api/outbox (POST) — client changes accepted by the host ---
    if (path == '/api/outbox' && request.method == 'POST') {
      await _withSyncAuth(request, _handleOutbox);
      return;
    }

    // --- /api/changes (GET) — delta pull for a client cursor ---
    if (path == '/api/changes' && request.method == 'GET') {
      await _withSyncAuth(request, _handleChanges);
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    request.response.write('POS LAN Server - Not Found');
    await request.response.close();
  }

  /// Rejects sync traffic before it is parsed unless the station proves it
  /// knows the pairing PIN.
  Future<void> _withSyncAuth(
    HttpRequest request,
    Future<void> Function(HttpRequest request) handler,
  ) async {
    final pin = (_securityPin ?? '').trim();
    if (pin.isEmpty) {
      request.response.statusCode = HttpStatus.forbidden;
      _writeJson(request, {
        'ok': false,
        'error': 'pin_required',
        'message': 'Set a security PIN on the host station to enable sync.',
      });
      return;
    }
    final stationId = request.headers.value('X-Station-Id') ?? '';
    final token = request.headers.value('X-Auth-Token');
    if (!verifySyncToken(pin: pin, stationId: stationId, token: token)) {
      request.response.statusCode = HttpStatus.unauthorized;
      _writeJson(request, {'ok': false, 'error': 'unauthorized'});
      return;
    }
    await handler(request);
  }

  Future<void> _handleHello(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final schemaVersion = json['schemaVersion'] as int? ?? -1;
      final clientLastRev = json['lastRev'] as int? ?? 0;

      if (schemaVersion != AppDatabase.currentSchemaVersion) {
        request.response.statusCode = HttpStatus.upgradeRequired;
        _writeJson(request, {
          'ok': false,
          'error': 'schema_mismatch',
          'schemaVersion': AppDatabase.currentSchemaVersion,
        });
        return;
      }

      final serverRev = await currentRev(_db);
      _writeJson(request, {
        'ok': true,
        'schemaVersion': AppDatabase.currentSchemaVersion,
        'serverRev': serverRev,
        // The host database was rebuilt under us: start the cursor over.
        'forceFullSync': clientLastRev > serverRev,
      });
    } catch (e) {
      debugPrint('[LanDatabaseServer] /api/hello error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      _writeJson(request, {'ok': false, 'error': e.toString()});
    }
  }

  Future<void> _handleHeartbeat(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final id = json['id'] as String? ?? '';
      final stationName = json['stationName'] as String? ?? 'Unknown Terminal';
      final clientIp =
          request.connectionInfo?.remoteAddress.address ?? '0.0.0.0';

      if (id.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        _writeJson(request, {'ok': false});
        return;
      }

      if (_clients.containsKey(id)) {
        _clients[id]!.lastHeartbeat = DateTime.now();
      } else {
        _clients[id] = ConnectedClientSession(
          id: id,
          remoteIp: clientIp,
          stationName: stationName,
          connectedAt: DateTime.now(),
        );
        debugPrint('[LanDatabaseServer] New client: $stationName ($clientIp)');
        _notifyClients();
      }

      _writeJson(request, {
        'ok': true,
        'serverTime': DateTime.now().toIso8601String(),
        'serverRev': await currentRev(_db),
        'schemaVersion': AppDatabase.currentSchemaVersion,
      });
    } catch (e) {
      debugPrint('[LanDatabaseServer] /api/heartbeat error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      _writeJson(request, {'ok': false});
    }
  }

  /// Returns every row with `rev >= since`, oldest first, up to [limit].
  ///
  /// Paging finds the boundary revision first so a page can never split a
  /// revision across requests — a client always resumes with
  /// `since = lastRev it applied`, which is idempotent because applying a row
  /// twice is a no-op.
  Future<void> _handleChanges(HttpRequest request) async {
    try {
      final since =
          int.tryParse(request.uri.queryParameters['since'] ?? '') ?? 0;
      var limit =
          int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 500;
      if (limit < 1) limit = 1;
      if (limit > 2000) limit = 2000;

      final union = [
        for (final spec in syncTables)
          'SELECT rev FROM "${spec.table}" WHERE rev >= ?',
      ].join(' UNION ALL ');
      final boundaryRows = await _db.customSelect(
        'SELECT rev FROM ($union) ORDER BY rev ASC LIMIT 1 OFFSET ?',
        variables: [
          for (var i = 0; i < syncTables.length; i++) Variable.withInt(since),
          Variable.withInt(limit - 1),
        ],
      ).get();
      final rawBoundary =
          boundaryRows.isEmpty ? null : boundaryRows.first.read<int>('rev');
      // A revision older than the cursor means `limit` rows share one
      // revision; revs are unique per row in practice, so this is a guard
      // against paging forever on the same cursor.
      final boundary =
          rawBoundary != null && rawBoundary > since ? rawBoundary : null;

      final changes = <Map<String, dynamic>>[];
      var lastRev = since;
      for (final spec in syncTables) {
        final info = _infos[spec.table]!;
        final rows = await selectSyncRows(
          _db,
          info,
          where: boundary != null
              ? 'rev >= $since AND rev <= $boundary'
              : 'rev >= $since',
        );
        for (final row in rows) {
          final payload = row.toJson();
          if (spec.table == 'settings' &&
              !isSharedSettingKey(payload['key'] as String? ?? '')) {
            continue;
          }
          final rev = payload['rev'] as int;
          if (rev > lastRev) lastRev = rev;
          changes.add({'table': spec.table, 'rev': rev, 'row': payload});
        }
      }
      changes.sort((a, b) => (a['rev'] as int).compareTo(b['rev'] as int));

      _writeJson(request, {
        'ok': true,
        'since': since,
        'lastRev': boundary ?? lastRev,
        'serverRev': await currentRev(_db),
        'hasMore': boundary != null,
        'changes': changes,
      });
    } catch (e) {
      debugPrint('[LanDatabaseServer] /api/changes error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      _writeJson(request, {'ok': false, 'error': e.toString()});
    }
  }

  /// Accepts a batch of client operations.
  ///
  /// Catalog rows are conflict-checked against `baseRev` (the revision the
  /// client last saw); transaction rows are appended once, keyed by primary
  /// key, so a retried push is a no-op.
  Future<void> _handleOutbox(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final ops = (json['ops'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      final results = <Map<String, dynamic>>[];
      for (final op in ops) {
        results.add(await _applyOp(op));
      }

      _writeJson(request, {'ok': true, 'results': results});
    } catch (e) {
      debugPrint('[LanDatabaseServer] /api/outbox error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      _writeJson(request, {'ok': false, 'error': e.toString()});
    }
  }

  Future<Map<String, dynamic>> _applyOp(Map<String, dynamic> op) async {
    final opId = op['opId'] as String? ?? '';
    final table = op['table'] as String? ?? '';
    final payload = op['payload'] as Map<String, dynamic>?;
    final spec = syncSpecFor(table);
    if (spec == null || spec.fromJson == null || payload == null) {
      return {'opId': opId, 'status': 'error', 'message': 'unsupported op'};
    }

    final info = _infos[table]!;
    final pk = syncPrimaryKey(table);
    final entityId = payload[pk]?.toString() ?? '';
    if (entityId.isEmpty) {
      return {'opId': opId, 'status': 'error', 'message': 'missing key'};
    }
    if (table == 'settings' && !isSharedSettingKey(entityId)) {
      return {'opId': opId, 'status': 'ignored'};
    }

    final row = spec.fromJson!(payload)!;
    final existing = await readSyncRowMeta(_db, table, entityId);

    if (existing != null && spec.kind == SyncKind.tx) {
      return {'opId': opId, 'status': 'duplicate', 'rev': existing.rev};
    }
    if (existing != null && (op['baseRev'] as int? ?? -1) != existing.rev) {
      return {
        'opId': opId,
        'status': 'conflict',
        'code': 'stale',
        'rev': existing.rev,
        'row': await readSyncRowJson(_db, table, info, entityId),
      };
    }

    final rev = await nextRev(_db);
    try {
      await writeSyncRow(
        _db,
        table: table,
        info: info,
        row: row,
        entityId: entityId,
        rev: rev,
        dirty: false,
      );
    } catch (e) {
      final unique = await _uniqueConflict(opId, table, info, payload, e);
      return unique ??
          <String, dynamic>{'opId': opId, 'status': 'error', 'message': '$e'};
    }
    return {'opId': opId, 'status': 'applied', 'rev': rev};
  }

  /// Turns a UNIQUE violation into a conflict carrying the row that owns the
  /// value (same SKU on two stations, same receipt number, …) so the client
  /// can resolve it instead of retrying forever.
  Future<Map<String, dynamic>?> _uniqueConflict(
    String opId,
    String table,
    TableInfo<Table, DataClass> info,
    Map<String, dynamic> payload,
    Object error,
  ) async {
    final match = RegExp(
      r'UNIQUE constraint failed:\s*[\w]+\.(?<column>\w+)',
    ).firstMatch(error.toString());
    final column = match?.namedGroup('column');
    if (column == null) return null;
    final value = payload[column];
    if (value is! String || value.isEmpty) return null;

    final rows = await selectSyncRows(
      _db,
      info,
      where: '"$column" = ${sqlLiteral(value)}',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final clash = rows.first.toJson();
    return {
      'opId': opId,
      'status': 'conflict',
      'code': 'unique',
      'column': column,
      'rev': clash['rev'],
      'row': clash,
    };
  }

  Future<void> _handleAuth(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final username = (json['username'] as String? ?? '').trim().toLowerCase();
      final password = json['password'] as String? ?? '';

      if (username.isEmpty || password.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        _writeJson(request, {'success': false, 'message': 'Missing credentials'});
        return;
      }

      final row = await (_db.select(_db.users)
            ..where((u) => u.username.equals(username)))
          .getSingleOrNull();

      if (row == null || !row.isActive || !verifyPassword(password, row.passwordHash)) {
        request.response.statusCode = HttpStatus.unauthorized;
        _writeJson(request, {'success': false, 'message': 'Invalid username or password'});
        return;
      }

      _writeJson(request, {
        'success': true,
        'user': {
          'id': row.id,
          'username': row.username,
          'displayName': row.displayName,
          'passwordHash': row.passwordHash,
          'role': row.role,
          'isActive': row.isActive,
          'createdAt': row.createdAt.toIso8601String(),
        },
      });
    } catch (e) {
      debugPrint('[LanDatabaseServer] /auth error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      _writeJson(request, {'success': false, 'message': 'Server error'});
    }
  }

  void _writeJson(HttpRequest request, Object data) {
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(data));
    request.response.close();
  }

  /// Disconnects a specific secondary terminal by session ID.
  Future<void> disconnectClient(String sessionId) async {
    if (_clients.containsKey(sessionId)) {
      final session = _clients.remove(sessionId);
      _notifyClients();
      debugPrint('[LanDatabaseServer] Disconnected by host: ${session?.stationName}');
    }
  }

  /// Stops the server.
  Future<void> stop() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _clients.clear();
    connectedClientsNotifier.value = [];
    activeClientsNotifier.value = 0;
    await _server?.close(force: true);
    _server = null;
    isRunningNotifier.value = false;
    debugPrint('[LanDatabaseServer] Stopped.');
  }

  /// Discovers local network IPv4 addresses of this host PC.
  static Future<List<String>> getLocalIpAddresses() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) {
            ips.add(address.address);
          }
        }
      }
    } catch (e) {
      debugPrint('[LanDatabaseServer] Error getting local IPs: $e');
    }
    if (ips.isEmpty) ips.add('127.0.0.1');
    return ips;
  }
}
