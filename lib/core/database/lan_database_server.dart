import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/core/security/passwords.dart';

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

/// LAN Server that exposes the local SQLite database to secondary POS terminals
/// over the local store network via a simple HTTP REST API.
///
/// Design: stateless HTTP endpoints — no persistent WebSocket connections.
/// Presence is tracked via periodic heartbeats from each client terminal.
class LanDatabaseServer {
  LanDatabaseServer(this._db);

  final AppDatabase _db;
  HttpServer? _server;
  String? _securityPin;

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

      // Expire stale clients every 15s
      _expiryTimer = Timer.periodic(const Duration(seconds: 15), (_) => _expireStaleClients());

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

    // CORS
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Origin, Content-Type, X-Auth-Token, X-Station-Name, X-Station-Id');

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
        debugPrint('[LanDatabaseServer] Client disconnected gracefully: ${session?.stationName}');
      }
      _writeJson(request, {'ok': true});
      return;
    }

    // --- /api/catalog (GET) — full catalog and stock dump for client sync ---
    if (path == '/api/catalog' && request.method == 'GET') {
      await _handleCatalog(request);
      return;
    }

    // --- /api/sales (POST) — client uploads offline sales ---
    if (path == '/api/sales' && request.method == 'POST') {
      await _handleSalesUpload(request);
      return;
    }

    // --- /api/sync/push (POST) — client uploads changes made on workstation ---
    if (path == '/api/sync/push' && request.method == 'POST') {
      await _handleClientPush(request);
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    request.response.write('POS LAN Server - Not Found');
    await request.response.close();
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

  Future<void> _handleHeartbeat(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final id = json['id'] as String? ?? '';
      final stationName = json['stationName'] as String? ?? 'Unknown Terminal';
      final clientIp = request.connectionInfo?.remoteAddress.address ?? '0.0.0.0';

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

      _writeJson(request, {'ok': true, 'serverTime': DateTime.now().toIso8601String()});
    } catch (e) {
      debugPrint('[LanDatabaseServer] /api/heartbeat error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      _writeJson(request, {'ok': false});
    }
  }

  Future<void> _handleCatalog(HttpRequest request) async {
    try {
      final users = await _db.select(_db.users).get();
      final categories = await _db.select(_db.categories).get();
      final brands = await _db.select(_db.brands).get();
      final products = await _db.select(_db.products).get();
      final settings = await _db.select(_db.settings).get();
      final movements = await _db.select(_db.stockMovements).get();
      final sales = await (_db.select(_db.sales)
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)])
            ..limit(250))
          .get();
      final saleIds = sales.map((s) => s.id).toSet();
      final saleItems = saleIds.isEmpty
          ? <SaleItem>[]
          : await (_db.select(_db.saleItems)..where((i) => i.saleId.isIn(saleIds))).get();
      final payments = saleIds.isEmpty
          ? <Payment>[]
          : await (_db.select(_db.payments)..where((p) => p.saleId.isIn(saleIds))).get();

      _writeJson(request, {
        'users': [
          for (final u in users)
            {
              'id': u.id,
              'username': u.username,
              'displayName': u.displayName,
              'passwordHash': u.passwordHash,
              'role': u.role,
              'isActive': u.isActive,
              'createdAt': u.createdAt.toIso8601String(),
            },
        ],
        'categories': [
          for (final c in categories)
            {
              'id': c.id,
              'name': c.name,
              'description': c.description,
              'createdAt': c.createdAt.toIso8601String(),
              'updatedAt': c.updatedAt.toIso8601String(),
            },
        ],
        'brands': [
          for (final b in brands)
            {
              'id': b.id,
              'name': b.name,
              'description': b.description,
              'createdAt': b.createdAt.toIso8601String(),
              'updatedAt': b.updatedAt.toIso8601String(),
            },
        ],
        'products': [
          for (final p in products)
            {
              'id': p.id,
              'sku': p.sku,
              'barcode': p.barcode,
              'name': p.name,
              'categoryId': p.categoryId,
              'brandId': p.brandId,
              'description': p.description,
              'costPrice': p.costPrice,
              'sellingPrice': p.sellingPrice,
              'taxRate': p.taxRate,
              'reorderLevel': p.reorderLevel,
              'trackingType': p.trackingType.name,
              'isActive': p.isActive,
              'createdAt': p.createdAt.toIso8601String(),
              'updatedAt': p.updatedAt.toIso8601String(),
            },
        ],
        'settings': [
          for (final s in settings)
            {
              'key': s.key,
              'value': s.value,
              'updatedAt': s.updatedAt.toIso8601String(),
            },
        ],
        'stockMovements': [
          for (final m in movements)
            {
              'id': m.id,
              'productId': m.productId,
              'movementType': m.movementType.name,
              'quantity': m.quantity,
              'referenceType': m.referenceType,
              'referenceId': m.referenceId,
              'userId': m.userId,
              'reason': m.reason,
              'createdAt': m.createdAt.toIso8601String(),
            },
        ],
        'sales': [
          for (final s in sales)
            {
              'id': s.id,
              'receiptNumber': s.receiptNumber,
              'customerId': s.customerId,
              'cashierId': s.cashierId,
              'subtotal': s.subtotal,
              'discount': s.discount,
              'tax': s.tax,
              'total': s.total,
              'paymentStatus': s.paymentStatus,
              'saleStatus': s.saleStatus,
              'createdAt': s.createdAt.toIso8601String(),
              'updatedAt': s.updatedAt.toIso8601String(),
            },
        ],
        'saleItems': [
          for (final i in saleItems)
            {
              'id': i.id,
              'saleId': i.saleId,
              'productId': i.productId,
              'quantity': i.quantity,
              'unitPrice': i.unitPrice,
              'discount': i.discount,
              'tax': i.tax,
              'subtotal': i.subtotal,
              'serialNumberId': i.serialNumberId,
            },
        ],
        'payments': [
          for (final p in payments)
            {
              'id': p.id,
              'saleId': p.saleId,
              'paymentMethod': p.paymentMethod.name,
              'amount': p.amount,
              'reference': p.reference,
              'createdAt': p.createdAt.toIso8601String(),
            },
        ],
      });
    } catch (e) {
      debugPrint('[LanDatabaseServer] /api/catalog error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      _writeJson(request, {'error': e.toString()});
    }
  }

  Future<void> _handleSalesUpload(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final salesList = json['sales'] as List<dynamic>? ?? [];
      int synced = 0;

      for (final saleJson in salesList) {
        final sale = saleJson as Map<String, dynamic>;
        final saleId = sale['id'] as String;
        final items = (sale['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        final payments = (sale['payments'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

        try {
          await _db.transaction(() async {
            final now = DateTime.now();
            final createdAt = sale['createdAt'] != null
                ? DateTime.parse(sale['createdAt'] as String)
                : now;
            final updatedAt = sale['updatedAt'] != null
                ? DateTime.parse(sale['updatedAt'] as String)
                : now;

            final existingSale = await (_db.select(_db.sales)
                  ..where((s) => s.id.equals(saleId)))
                .getSingleOrNull();

            if (existingSale != null) {
              await (_db.update(_db.sales)..where((s) => s.id.equals(saleId)))
                  .write(
                SalesCompanion(
                  receiptNumber: Value(sale['receiptNumber'] as String),
                  customerId: Value(sale['customerId'] as String?),
                  cashierId: Value(sale['cashierId'] as String?),
                  subtotal: Value((sale['subtotal'] as num).toDouble()),
                  discount: Value((sale['discount'] as num? ?? 0).toDouble()),
                  tax: Value((sale['tax'] as num? ?? 0).toDouble()),
                  total: Value((sale['total'] as num).toDouble()),
                  paymentStatus: Value(sale['paymentStatus'] as String? ?? 'PAID'),
                  saleStatus: Value(sale['saleStatus'] as String? ?? 'COMPLETED'),
                  isSynced: const Value(true),
                  updatedAt: Value(updatedAt),
                ),
              );
            } else {
              await _db.into(_db.sales).insert(
                SalesCompanion(
                  id: Value(saleId),
                  receiptNumber: Value(sale['receiptNumber'] as String),
                  customerId: Value(sale['customerId'] as String?),
                  cashierId: Value(sale['cashierId'] as String?),
                  subtotal: Value((sale['subtotal'] as num).toDouble()),
                  discount: Value((sale['discount'] as num? ?? 0).toDouble()),
                  tax: Value((sale['tax'] as num? ?? 0).toDouble()),
                  total: Value((sale['total'] as num).toDouble()),
                  paymentStatus: Value(sale['paymentStatus'] as String? ?? 'PAID'),
                  saleStatus: Value(sale['saleStatus'] as String? ?? 'COMPLETED'),
                  isSynced: const Value(true),
                  createdAt: Value(createdAt),
                  updatedAt: Value(updatedAt),
                ),
              );
            }

            for (final item in items) {
              final itemId = item['id'] as String;
              final qty = (item['quantity'] as num).toDouble();
              final unitPrice = (item['unitPrice'] as num).toDouble();
              final discount = (item['discount'] as num? ?? 0).toDouble();
              final tax = (item['tax'] as num? ?? 0).toDouble();
              final subtotal = (item['subtotal'] as num? ?? (qty * unitPrice)).toDouble();

              final existingItem = await (_db.select(_db.saleItems)
                    ..where((i) => i.id.equals(itemId)))
                  .getSingleOrNull();

              if (existingItem != null) {
                await (_db.update(_db.saleItems)..where((i) => i.id.equals(itemId)))
                    .write(
                  SaleItemsCompanion(
                    quantity: Value(qty),
                    unitPrice: Value(unitPrice),
                    discount: Value(discount),
                    tax: Value(tax),
                    subtotal: Value(subtotal),
                    serialNumberId: Value(item['serialNumberId'] as String?),
                  ),
                );
              } else {
                await _db.into(_db.saleItems).insert(
                  SaleItemsCompanion(
                    id: Value(itemId),
                    saleId: Value(saleId),
                    productId: Value(item['productId'] as String),
                    quantity: Value(qty),
                    unitPrice: Value(unitPrice),
                    discount: Value(discount),
                    tax: Value(tax),
                    subtotal: Value(subtotal),
                    serialNumberId: Value(item['serialNumberId'] as String?),
                  ),
                );
              }

              final existingMovement = await (_db.select(_db.stockMovements)
                    ..where((m) =>
                        m.referenceId.equals(saleId) &
                        m.productId.equals(item['productId'] as String)))
                  .getSingleOrNull();

              if (existingMovement == null) {
                await _db.into(_db.stockMovements).insert(
                  StockMovementsCompanion(
                    id: Value('sync-$saleId-$itemId'),
                    productId: Value(item['productId'] as String),
                    movementType: const Value(MovementType.sale),
                    quantity: Value(-qty),
                    referenceType: const Value<String?>('sale'),
                    referenceId: Value<String?>(saleId),
                    userId: Value<String?>(sale['cashierId'] as String?),
                    reason: const Value<String?>('LAN station sync'),
                    createdAt: Value(createdAt),
                  ),
                );
              }
            }

            for (final payment in payments) {
              final paymentId = payment['id'] as String;
              PaymentMethod method = PaymentMethod.cash;
              final mStr = payment['paymentMethod'] as String? ?? payment['method'] as String? ?? 'cash';
              try {
                method = PaymentMethod.values.byName(mStr);
              } catch (_) {
                method = PaymentMethod.cash;
              }

              final existingPayment = await (_db.select(_db.payments)
                    ..where((p) => p.id.equals(paymentId)))
                  .getSingleOrNull();

              if (existingPayment != null) {
                await (_db.update(_db.payments)..where((p) => p.id.equals(paymentId)))
                    .write(
                  PaymentsCompanion(
                    paymentMethod: Value(method),
                    amount: Value((payment['amount'] as num).toDouble()),
                    reference: Value(payment['reference'] as String?),
                  ),
                );
              } else {
                await _db.into(_db.payments).insert(
                  PaymentsCompanion(
                    id: Value(paymentId),
                    saleId: Value(saleId),
                    paymentMethod: Value(method),
                    amount: Value((payment['amount'] as num).toDouble()),
                    reference: Value(payment['reference'] as String?),
                    createdAt: Value(payment['createdAt'] != null
                        ? DateTime.parse(payment['createdAt'] as String)
                        : createdAt),
                  ),
                );
              }
            }
          });
          synced++;
        } catch (e) {
          debugPrint('[LanDatabaseServer] Failed to save sale $saleId: $e');
        }
      }

      // Notify host UI that new data arrived
      _db.markTablesUpdated({_db.sales, _db.saleItems, _db.payments, _db.stockMovements});

      _writeJson(request, {'ok': true, 'synced': synced});
    } catch (e) {
      debugPrint('[LanDatabaseServer] /api/sales error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      _writeJson(request, {'ok': false, 'error': e.toString()});
    }
  }

  Future<void> _handleClientPush(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      await _db.transaction(() async {
        // Categories
        for (final c in (json['categories'] as List<dynamic>? ?? [])) {
          final map = c as Map<String, dynamic>;
          final id = map['id'] as String;
          final name = map['name'] as String;
          final existing = await (_db.select(_db.categories)
                ..where((cat) => cat.id.equals(id) | cat.name.equals(name)))
              .getSingleOrNull();
          if (existing != null) {
            await (_db.update(_db.categories)..where((cat) => cat.id.equals(existing.id)))
                .write(CategoriesCompanion(
              id: Value(id),
              name: Value(name),
              description: Value(map['description'] as String?),
              updatedAt: Value(DateTime.parse(map['updatedAt'] as String)),
            ));
          } else {
            await _db.into(_db.categories).insert(CategoriesCompanion.insert(
              id: id,
              name: name,
              description: Value(map['description'] as String?),
              createdAt: Value(DateTime.parse(map['createdAt'] as String)),
              updatedAt: Value(DateTime.parse(map['updatedAt'] as String)),
            ));
          }
        }

        // Brands
        for (final b in (json['brands'] as List<dynamic>? ?? [])) {
          final map = b as Map<String, dynamic>;
          final id = map['id'] as String;
          final name = map['name'] as String;
          final existing = await (_db.select(_db.brands)
                ..where((brd) => brd.id.equals(id) | brd.name.equals(name)))
              .getSingleOrNull();
          if (existing != null) {
            await (_db.update(_db.brands)..where((brd) => brd.id.equals(existing.id)))
                .write(BrandsCompanion(
              id: Value(id),
              name: Value(name),
              description: Value(map['description'] as String?),
              updatedAt: Value(DateTime.parse(map['updatedAt'] as String)),
            ));
          } else {
            await _db.into(_db.brands).insert(BrandsCompanion.insert(
              id: id,
              name: name,
              description: Value(map['description'] as String?),
              createdAt: Value(DateTime.parse(map['createdAt'] as String)),
              updatedAt: Value(DateTime.parse(map['updatedAt'] as String)),
            ));
          }
        }

        // Products
        for (final p in (json['products'] as List<dynamic>? ?? [])) {
          final map = p as Map<String, dynamic>;
          final id = map['id'] as String;
          final sku = map['sku'] as String;
          ProductTrackingType trackingType = ProductTrackingType.quantity;
          if (map['trackingType'] == 'serialized') {
            trackingType = ProductTrackingType.serialized;
          }
          final existing = await (_db.select(_db.products)
                ..where((prd) => prd.id.equals(id) | prd.sku.equals(sku)))
              .getSingleOrNull();
          if (existing != null) {
            await (_db.update(_db.products)..where((prd) => prd.id.equals(existing.id)))
                .write(ProductsCompanion(
              id: Value(id),
              sku: Value(sku),
              barcode: Value(map['barcode'] as String?),
              name: Value(map['name'] as String),
              categoryId: Value(map['categoryId'] as String?),
              brandId: Value(map['brandId'] as String?),
              description: Value(map['description'] as String?),
              costPrice: Value((map['costPrice'] as num).toDouble()),
              sellingPrice: Value((map['sellingPrice'] as num).toDouble()),
              taxRate: Value((map['taxRate'] as num? ?? 0).toDouble()),
              reorderLevel: Value((map['reorderLevel'] as num? ?? 0).toDouble()),
              trackingType: Value(trackingType),
              isActive: Value(map['isActive'] as bool? ?? true),
              updatedAt: Value(DateTime.parse(map['updatedAt'] as String)),
            ));
          } else {
            await _db.into(_db.products).insert(ProductsCompanion.insert(
              id: id,
              sku: sku,
              barcode: Value(map['barcode'] as String?),
              name: map['name'] as String,
              categoryId: Value(map['categoryId'] as String?),
              brandId: Value(map['brandId'] as String?),
              description: Value(map['description'] as String?),
              costPrice: (map['costPrice'] as num).toDouble(),
              sellingPrice: (map['sellingPrice'] as num).toDouble(),
              taxRate: Value((map['taxRate'] as num? ?? 0).toDouble()),
              reorderLevel: Value((map['reorderLevel'] as num? ?? 0).toDouble()),
              trackingType: Value(trackingType),
              isActive: Value(map['isActive'] as bool? ?? true),
              createdAt: Value(DateTime.parse(map['createdAt'] as String)),
              updatedAt: Value(DateTime.parse(map['updatedAt'] as String)),
            ));
          }
        }

        // StockMovements from Client
        for (final m in (json['stockMovements'] as List<dynamic>? ?? [])) {
          final map = m as Map<String, dynamic>;
          final id = map['id'] as String;
          final existing = await (_db.select(_db.stockMovements)
                ..where((mov) => mov.id.equals(id)))
              .getSingleOrNull();
          if (existing == null) {
            MovementType type = MovementType.adjustment;
            try {
              type = MovementType.values.byName(map['movementType'] as String);
            } catch (_) {}
            await _db.into(_db.stockMovements).insert(StockMovementsCompanion(
              id: Value(id),
              productId: Value(map['productId'] as String),
              movementType: Value(type),
              quantity: Value((map['quantity'] as num).toDouble()),
              referenceType: Value(map['referenceType'] as String?),
              referenceId: Value(map['referenceId'] as String?),
              userId: Value(map['userId'] as String?),
              reason: Value(map['reason'] as String?),
              createdAt: Value(DateTime.parse(map['createdAt'] as String)),
            ));
          }
        }
      });

      _db.markTablesUpdated({
        _db.products,
        _db.categories,
        _db.brands,
        _db.stockMovements,
      });

      _writeJson(request, {'ok': true});
    } catch (e) {
      debugPrint('[LanDatabaseServer] /api/sync/push error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      _writeJson(request, {'ok': false, 'error': e.toString()});
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
