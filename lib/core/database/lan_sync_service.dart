import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/core/database/workstation_config.dart';
import 'package:uuid/uuid.dart';

/// Background synchronization service using pure HTTP REST calls.
///
/// Features:
/// - Heartbeat POST every 10s   → maintains terminal presence on Host
/// - Catalog GET every 5s       → pulls users, products, stock movements, and sales from Host
/// - Sales POST on each sale    → pushes client sales immediately to Host
/// - Changes POST on edit       → pushes locally added/modified products and stock to Host
class LanSyncService {
  LanSyncService(this._localDb) {
    instance = this;
  }

  static LanSyncService? instance;

  /// Globally trigger immediate sync from anywhere in the app (e.g. checkout).
  static void triggerSync() {
    instance?.syncNow();
  }

  final AppDatabase _localDb;
  final String _stationId = const Uuid().v4();

  Timer? _heartbeatTimer;
  Timer? _catalogTimer;
  bool _isStarted = false;
  bool _isSyncing = false;

  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> pendingSyncCountNotifier = ValueNotifier<int>(0);

  static const _catalogInterval = Duration(seconds: 5);
  static const _heartbeatInterval = Duration(seconds: 10);
  static const _httpTimeout = Duration(seconds: 6);

  void start() {
    if (_isStarted) return;
    _isStarted = true;

    final config = WorkstationConfig.current;
    if (!config.isClient || config.hostAddress.isEmpty) {
      isOnlineNotifier.value = true;
      return;
    }

    // Run immediately on start, then on fast intervals
    _sendHeartbeat();
    _pushOfflineSales();
    _syncCatalog();

    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _sendHeartbeat());
    _catalogTimer = Timer.periodic(_catalogInterval, (_) async {
      await _pushOfflineSales();
      await _pushClientChanges();
      await _syncCatalog();
    });
  }

  void stop() {
    if (!_isStarted) return;
    _isStarted = false;
    _heartbeatTimer?.cancel();
    _catalogTimer?.cancel();
    _heartbeatTimer = null;
    _catalogTimer = null;
    _unregister(); // best-effort graceful unregister
    isOnlineNotifier.value = false;
  }

  /// Called after a sale or inventory change is completed to push immediately.
  Future<void> syncNow() async {
    final config = WorkstationConfig.current;
    if (!config.isClient || config.hostAddress.isEmpty) return;
    await _pushOfflineSales();
    await _pushClientChanges();
    await _syncCatalog();
  }

  // ── Heartbeat ────────────────────────────────────────────────────────────

  Future<void> _sendHeartbeat() async {
    final config = WorkstationConfig.current;
    if (!config.isClient || config.hostAddress.isEmpty) return;

    final client = HttpClient()..connectionTimeout = _httpTimeout;
    try {
      final uri = Uri.http('${config.hostAddress}:${config.hostPort}', '/api/heartbeat');
      final request = await client.postUrl(uri).timeout(_httpTimeout);
      request.headers.contentType = ContentType.json;
      final body = jsonEncode({
        'id': _stationId,
        'stationName': config.stationName.isNotEmpty
            ? config.stationName
            : Platform.localHostname,
      });
      request.headers.contentLength = utf8.encode(body).length;
      request.write(body);
      final response = await request.close().timeout(_httpTimeout);
      await response.drain<void>();
      isOnlineNotifier.value = response.statusCode == HttpStatus.ok;
    } catch (e) {
      isOnlineNotifier.value = false;
      debugPrint('[LanSyncService] Heartbeat failed: $e');
    } finally {
      client.close();
    }
  }

  Future<void> _unregister() async {
    final config = WorkstationConfig.current;
    if (!config.isClient || config.hostAddress.isEmpty) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final uri = Uri.http('${config.hostAddress}:${config.hostPort}', '/api/heartbeat/$_stationId');
      final request = await client.deleteUrl(uri).timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 2));
      await response.drain<void>();
    } catch (_) {
      // Best-effort — server will expire us after 45s anyway
    } finally {
      client.close();
    }
  }

  // ── Catalog & Stock Sync (Host → Client) ──────────────────────────────────

  Future<void> _syncCatalog() async {
    if (_isSyncing) return;
    final config = WorkstationConfig.current;
    if (!config.isClient || config.hostAddress.isEmpty) return;

    _isSyncing = true;
    final client = HttpClient()..connectionTimeout = _httpTimeout;
    try {
      final uri = Uri.http('${config.hostAddress}:${config.hostPort}', '/api/catalog');
      final request = await client.getUrl(uri).timeout(_httpTimeout);
      final response = await request.close().timeout(_httpTimeout);

      if (response.statusCode != HttpStatus.ok) {
        debugPrint('[LanSyncService] Catalog sync: bad status ${response.statusCode}');
        return;
      }

      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      await _localDb.transaction(() async {
        // Users
        for (final u in (data['users'] as List<dynamic>? ?? [])) {
          final map = u as Map<String, dynamic>;
          final id = map['id'] as String;
          final username = map['username'] as String;
          final createdAt = map['createdAt'] != null
              ? DateTime.parse(map['createdAt'] as String)
              : DateTime.now();

          final existing = await (_localDb.select(_localDb.users)
                ..where((usr) => usr.id.equals(id) | usr.username.equals(username)))
              .getSingleOrNull();

          if (existing != null) {
            await (_localDb.update(_localDb.users)
                  ..where((usr) => usr.id.equals(existing.id)))
                .write(
              UsersCompanion(
                id: Value(id),
                username: Value(username),
                displayName: Value(map['displayName'] as String),
                passwordHash: Value(map['passwordHash'] as String),
                role: Value(map['role'] as String),
                isActive: Value(map['isActive'] as bool? ?? true),
                createdAt: Value(createdAt),
              ),
            );
          } else {
            await _localDb.into(_localDb.users).insert(
              UsersCompanion.insert(
                id: id,
                username: username,
                displayName: map['displayName'] as String,
                passwordHash: map['passwordHash'] as String,
                role: map['role'] as String,
                isActive: Value(map['isActive'] as bool? ?? true),
                createdAt: Value(createdAt),
              ),
            );
          }
        }

        // Categories
        for (final c in (data['categories'] as List<dynamic>? ?? [])) {
          final map = c as Map<String, dynamic>;
          final id = map['id'] as String;
          final name = map['name'] as String;
          final createdAt = map['createdAt'] != null
              ? DateTime.parse(map['createdAt'] as String)
              : DateTime.now();
          final updatedAt = map['updatedAt'] != null
              ? DateTime.parse(map['updatedAt'] as String)
              : DateTime.now();

          final existing = await (_localDb.select(_localDb.categories)
                ..where((cat) => cat.id.equals(id) | cat.name.equals(name)))
              .getSingleOrNull();

          if (existing != null) {
            await (_localDb.update(_localDb.categories)
                  ..where((cat) => cat.id.equals(existing.id)))
                .write(
              CategoriesCompanion(
                id: Value(id),
                name: Value(name),
                description: Value(map['description'] as String?),
                createdAt: Value(createdAt),
                updatedAt: Value(updatedAt),
              ),
            );
          } else {
            await _localDb.into(_localDb.categories).insert(
              CategoriesCompanion.insert(
                id: id,
                name: name,
                description: Value(map['description'] as String?),
                createdAt: Value(createdAt),
                updatedAt: Value(updatedAt),
              ),
            );
          }
        }

        // Brands
        for (final b in (data['brands'] as List<dynamic>? ?? [])) {
          final map = b as Map<String, dynamic>;
          final id = map['id'] as String;
          final name = map['name'] as String;
          final createdAt = map['createdAt'] != null
              ? DateTime.parse(map['createdAt'] as String)
              : DateTime.now();
          final updatedAt = map['updatedAt'] != null
              ? DateTime.parse(map['updatedAt'] as String)
              : DateTime.now();

          final existing = await (_localDb.select(_localDb.brands)
                ..where((brd) => brd.id.equals(id) | brd.name.equals(name)))
              .getSingleOrNull();

          if (existing != null) {
            await (_localDb.update(_localDb.brands)
                  ..where((brd) => brd.id.equals(existing.id)))
                .write(
              BrandsCompanion(
                id: Value(id),
                name: Value(name),
                description: Value(map['description'] as String?),
                createdAt: Value(createdAt),
                updatedAt: Value(updatedAt),
              ),
            );
          } else {
            await _localDb.into(_localDb.brands).insert(
              BrandsCompanion.insert(
                id: id,
                name: name,
                description: Value(map['description'] as String?),
                createdAt: Value(createdAt),
                updatedAt: Value(updatedAt),
              ),
            );
          }
        }

        // Products
        for (final p in (data['products'] as List<dynamic>? ?? [])) {
          final map = p as Map<String, dynamic>;
          final id = map['id'] as String;
          final sku = map['sku'] as String;
          ProductTrackingType trackingType = ProductTrackingType.quantity;
          if (map['trackingType'] == 'serialized') {
            trackingType = ProductTrackingType.serialized;
          }
          final createdAt = map['createdAt'] != null
              ? DateTime.parse(map['createdAt'] as String)
              : DateTime.now();
          final updatedAt = map['updatedAt'] != null
              ? DateTime.parse(map['updatedAt'] as String)
              : DateTime.now();

          final existing = await (_localDb.select(_localDb.products)
                ..where((prd) => prd.id.equals(id) | prd.sku.equals(sku)))
              .getSingleOrNull();

          if (existing != null) {
            await (_localDb.update(_localDb.products)
                  ..where((prd) => prd.id.equals(existing.id)))
                .write(
              ProductsCompanion(
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
                createdAt: Value(createdAt),
                updatedAt: Value(updatedAt),
              ),
            );
          } else {
            await _localDb.into(_localDb.products).insert(
              ProductsCompanion.insert(
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
                createdAt: Value(createdAt),
                updatedAt: Value(updatedAt),
              ),
            );
          }
        }

        // Settings
        for (final s in (data['settings'] as List<dynamic>? ?? [])) {
          final map = s as Map<String, dynamic>;
          final key = map['key'] as String;
          final value = map['value'] as String;
          final updatedAt = map['updatedAt'] != null
              ? DateTime.parse(map['updatedAt'] as String)
              : DateTime.now();

          final existing = await (_localDb.select(_localDb.settings)
                ..where((st) => st.key.equals(key)))
              .getSingleOrNull();

          if (existing != null) {
            await (_localDb.update(_localDb.settings)
                  ..where((st) => st.key.equals(key)))
                .write(
              SettingsCompanion(
                key: Value(key),
                value: Value(value),
                updatedAt: Value(updatedAt),
              ),
            );
          } else {
            await _localDb.into(_localDb.settings).insert(
              SettingsCompanion.insert(
                key: key,
                value: value,
                updatedAt: Value(updatedAt),
              ),
            );
          }
        }

        // Stock Movements (Master ledger from Host)
        for (final m in (data['stockMovements'] as List<dynamic>? ?? [])) {
          final map = m as Map<String, dynamic>;
          final id = map['id'] as String;

          final existing = await (_localDb.select(_localDb.stockMovements)
                ..where((mov) => mov.id.equals(id)))
              .getSingleOrNull();

          if (existing == null) {
            MovementType type = MovementType.openingStock;
            try {
              type = MovementType.values.byName(map['movementType'] as String);
            } catch (_) {}

            await _localDb.into(_localDb.stockMovements).insert(
              StockMovementsCompanion(
                id: Value(id),
                productId: Value(map['productId'] as String),
                movementType: Value(type),
                quantity: Value((map['quantity'] as num).toDouble()),
                referenceType: Value(map['referenceType'] as String?),
                referenceId: Value(map['referenceId'] as String?),
                userId: Value(map['userId'] as String?),
                reason: Value(map['reason'] as String?),
                createdAt: Value(DateTime.parse(map['createdAt'] as String)),
              ),
            );
          }
        }

        // Sales from Host (so client has matching sales history)
        for (final s in (data['sales'] as List<dynamic>? ?? [])) {
          final map = s as Map<String, dynamic>;
          final id = map['id'] as String;

          final existing = await (_localDb.select(_localDb.sales)
                ..where((sale) => sale.id.equals(id)))
              .getSingleOrNull();

          if (existing == null) {
            await _localDb.into(_localDb.sales).insert(
              SalesCompanion(
                id: Value(id),
                receiptNumber: Value(map['receiptNumber'] as String),
                customerId: Value(map['customerId'] as String?),
                cashierId: Value(map['cashierId'] as String?),
                subtotal: Value((map['subtotal'] as num).toDouble()),
                discount: Value((map['discount'] as num? ?? 0).toDouble()),
                tax: Value((map['tax'] as num? ?? 0).toDouble()),
                total: Value((map['total'] as num).toDouble()),
                paymentStatus: Value(map['paymentStatus'] as String? ?? 'PAID'),
                saleStatus: Value(map['saleStatus'] as String? ?? 'COMPLETED'),
                isSynced: const Value(true),
                createdAt: Value(DateTime.parse(map['createdAt'] as String)),
                updatedAt: Value(DateTime.parse(map['updatedAt'] as String)),
              ),
            );
          }
        }

        // Sale Items from Host
        for (final item in (data['saleItems'] as List<dynamic>? ?? [])) {
          final map = item as Map<String, dynamic>;
          final id = map['id'] as String;

          final existing = await (_localDb.select(_localDb.saleItems)
                ..where((it) => it.id.equals(id)))
              .getSingleOrNull();

          if (existing == null) {
            await _localDb.into(_localDb.saleItems).insert(
              SaleItemsCompanion(
                id: Value(id),
                saleId: Value(map['saleId'] as String),
                productId: Value(map['productId'] as String),
                quantity: Value((map['quantity'] as num).toDouble()),
                unitPrice: Value((map['unitPrice'] as num).toDouble()),
                discount: Value((map['discount'] as num? ?? 0).toDouble()),
                tax: Value((map['tax'] as num? ?? 0).toDouble()),
                subtotal: Value((map['subtotal'] as num).toDouble()),
                serialNumberId: Value(map['serialNumberId'] as String?),
              ),
            );
          }
        }

        // Payments from Host
        for (final p in (data['payments'] as List<dynamic>? ?? [])) {
          final map = p as Map<String, dynamic>;
          final id = map['id'] as String;

          final existing = await (_localDb.select(_localDb.payments)
                ..where((pm) => pm.id.equals(id)))
              .getSingleOrNull();

          if (existing == null) {
            PaymentMethod method = PaymentMethod.cash;
            try {
              method = PaymentMethod.values.byName(map['paymentMethod'] as String);
            } catch (_) {}

            await _localDb.into(_localDb.payments).insert(
              PaymentsCompanion(
                id: Value(id),
                saleId: Value(map['saleId'] as String),
                paymentMethod: Value(method),
                amount: Value((map['amount'] as num).toDouble()),
                reference: Value(map['reference'] as String?),
                createdAt: Value(DateTime.parse(map['createdAt'] as String)),
              ),
            );
          }
        }
      });

      // Notify Riverpod streams across the client app that all tables have changed
      _localDb.markTablesUpdated({
        _localDb.users,
        _localDb.categories,
        _localDb.brands,
        _localDb.products,
        _localDb.settings,
        _localDb.stockMovements,
        _localDb.sales,
        _localDb.saleItems,
        _localDb.payments,
      });

      debugPrint('[LanSyncService] Full catalog + stock sync complete.');
    } catch (e) {
      debugPrint('[LanSyncService] Catalog sync error: $e');
    } finally {
      _isSyncing = false;
      client.close();
    }
  }

  // ── Sales push (Client → Host) ───────────────────────────────────────────

  Future<void> _pushOfflineSales() async {
    final config = WorkstationConfig.current;
    if (!config.isClient || config.hostAddress.isEmpty) return;

    try {
      final unsyncedSales = await (_localDb.select(_localDb.sales)
            ..where((s) => s.isSynced.equals(false)))
          .get();

      if (unsyncedSales.isEmpty) {
        pendingSyncCountNotifier.value = 0;
        return;
      }

      pendingSyncCountNotifier.value = unsyncedSales.length;

      final salesPayload = <Map<String, dynamic>>[];
      for (final sale in unsyncedSales) {
        final items = await (_localDb.select(_localDb.saleItems)
              ..where((i) => i.saleId.equals(sale.id)))
            .get();
        final payments = await (_localDb.select(_localDb.payments)
              ..where((p) => p.saleId.equals(sale.id)))
            .get();

        salesPayload.add({
          'id': sale.id,
          'receiptNumber': sale.receiptNumber,
          'customerId': sale.customerId,
          'cashierId': sale.cashierId,
          'subtotal': sale.subtotal,
          'discount': sale.discount,
          'tax': sale.tax,
          'total': sale.total,
          'paymentStatus': sale.paymentStatus,
          'saleStatus': sale.saleStatus,
          'createdAt': sale.createdAt.toIso8601String(),
          'updatedAt': sale.updatedAt.toIso8601String(),
          'items': [
            for (final item in items)
              {
                'id': item.id,
                'saleId': item.saleId,
                'productId': item.productId,
                'quantity': item.quantity,
                'unitPrice': item.unitPrice,
                'discount': item.discount,
                'tax': item.tax,
                'subtotal': item.subtotal,
                'serialNumberId': item.serialNumberId,
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
      }

      final client = HttpClient()..connectionTimeout = _httpTimeout;
      try {
        final uri = Uri.http('${config.hostAddress}:${config.hostPort}', '/api/sales');
        final request = await client.postUrl(uri).timeout(_httpTimeout);
        request.headers.contentType = ContentType.json;
        final body = jsonEncode({'sales': salesPayload});
        request.headers.contentLength = utf8.encode(body).length;
        request.write(body);
        final response = await request.close().timeout(_httpTimeout);
        final responseBody = await response.transform(utf8.decoder).join();

        if (response.statusCode == HttpStatus.ok) {
          final result = jsonDecode(responseBody) as Map<String, dynamic>;
          final synced = result['synced'] as int? ?? 0;
          if (synced > 0) {
            // Mark local sales as synced
            for (final sale in unsyncedSales.take(synced)) {
              await (_localDb.update(_localDb.sales)
                    ..where((s) => s.id.equals(sale.id)))
                  .write(const SalesCompanion(isSynced: Value(true)));
            }
            debugPrint('[LanSyncService] Pushed $synced offline sales to host.');
          }
        }
      } finally {
        client.close();
      }

      // Recount
      final remaining = await (_localDb.select(_localDb.sales)
            ..where((s) => s.isSynced.equals(false)))
          .get();
      pendingSyncCountNotifier.value = remaining.length;
    } catch (e) {
      debugPrint('[LanSyncService] Sales push error: $e');
    }
  }

  // ── Push Client-Created Products & Stock Movements (Client → Host) ─────────

  Future<void> _pushClientChanges() async {
    final config = WorkstationConfig.current;
    if (!config.isClient || config.hostAddress.isEmpty) return;

    try {
      final products = await _localDb.select(_localDb.products).get();
      final movements = await _localDb.select(_localDb.stockMovements).get();
      final categories = await _localDb.select(_localDb.categories).get();
      final brands = await _localDb.select(_localDb.brands).get();

      final client = HttpClient()..connectionTimeout = _httpTimeout;
      try {
        final uri = Uri.http('${config.hostAddress}:${config.hostPort}', '/api/sync/push');
        final request = await client.postUrl(uri).timeout(_httpTimeout);
        request.headers.contentType = ContentType.json;
        final body = jsonEncode({
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
        });
        request.headers.contentLength = utf8.encode(body).length;
        request.write(body);
        final response = await request.close().timeout(_httpTimeout);
        await response.drain<void>();
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[LanSyncService] Push client changes error: $e');
    }
  }
}

/// Singleton provider for the LAN synchronization service.
final lanSyncServiceProvider = Provider<LanSyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final service = LanSyncService(db);
  service.start();
  ref.onDispose(service.stop);
  return service;
});
