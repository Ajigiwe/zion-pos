import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/core/database/lan_database_client.dart';
import 'package:instrument_pos/core/database/lan_database_server.dart';
import 'package:instrument_pos/features/settings/data/settings_repository.dart';
import 'package:instrument_pos/features/settings/domain/network_settings.dart';
import 'package:instrument_pos/features/settings/presentation/network_settings_card.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';

class _AllowLoopbackHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowLoopbackHttpOverrides();

  group('NetworkSettings Domain & Repository Tests', () {
    test('default NetworkSettings is standalone with port 4242', () {
      const settings = NetworkSettings();
      expect(settings.mode, NetworkStationMode.standalone);
      expect(settings.isStandalone, isTrue);
      expect(settings.isHost, isFalse);
      expect(settings.isClient, isFalse);
      expect(settings.hostPort, 4242);
      expect(settings.remoteHostPort, 4242);
    });

    test('copyWith updates mode and ports accurately', () {
      const settings = NetworkSettings();
      final updated = settings.copyWith(
        mode: NetworkStationMode.host,
        hostPort: 8080,
        remoteHostAddress: '192.168.1.55',
        remoteHostPort: 8080,
        securityPin: '1234',
      );
      expect(updated.mode, NetworkStationMode.host);
      expect(updated.isHost, isTrue);
      expect(updated.hostPort, 8080);
      expect(updated.remoteHostAddress, '192.168.1.55');
      expect(updated.securityPin, '1234');
    });

    test('SettingsRepository persists and loads NetworkSettings', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = SettingsRepository(db);

      final initial = await repo.loadNetworkSettings();
      expect(initial.isStandalone, isTrue);

      const target = NetworkSettings(
        mode: NetworkStationMode.client,
        hostPort: 5050,
        remoteHostAddress: '192.168.1.99',
        remoteHostPort: 5050,
        securityPin: '9876',
      );

      await repo.saveNetworkSettings(target, actingUserId: 'admin-1');

      final loaded = await repo.loadNetworkSettings();
      expect(loaded.mode, NetworkStationMode.client);
      expect(loaded.hostPort, 5050);
      expect(loaded.remoteHostAddress, '192.168.1.99');
      expect(loaded.remoteHostPort, 5050);
      expect(loaded.securityPin, '9876');
    });
  });

  group('LanDatabaseServer & LanDatabaseClient Network Tests', () {
    late AppDatabase serverDb;
    late LanDatabaseServer server;

    setUp(() {
      serverDb = AppDatabase(NativeDatabase.memory());
      server = LanDatabaseServer(serverDb);
    });

    tearDown(() async {
      await server.stop();
      await serverDb.close();
    });

    test('starts server, responds to HTTP /status ping and discovers local IPs',
        () async {
      await server.start(port: 0);
      expect(server.isRunning, isTrue);
      final port = server.port;

      // Test client ping
      final ping = await LanDatabaseClient.testConnection('127.0.0.1', port);
      expect(ping.success, isTrue);
      expect(ping.serverData?['stationMode'], 'host');
      expect(ping.serverData?['status'], 'online');

      final ips = await LanDatabaseServer.getLocalIpAddresses();
      expect(ips, isNotEmpty);
    });

    test(
        'client sends heartbeat, server tracks client session, and can disconnect',
        () async {
      await server.start(port: 0);
      final port = server.port;

      expect(server.connectedClientsNotifier.value, isEmpty);

      // Send heartbeat
      final client = HttpClient();
      final uri = Uri.http('127.0.0.1:$port', '/api/heartbeat');
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      final body = jsonEncode({'id': 'station-test-1', 'stationName': 'Register 2 - Cashier Desk'});
      req.write(body);
      final res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      client.close();

      // Verify server registered the client session
      expect(server.connectedClientsNotifier.value.length, 1);
      final session = server.connectedClientsNotifier.value.first;
      expect(session.stationName, 'Register 2 - Cashier Desk');
      expect(session.remoteIp, isNotEmpty);

      // Disconnect client
      await server.disconnectClient(session.id);
      expect(server.connectedClientsNotifier.value, isEmpty);
    });
  });

  group('NetworkSettingsCard Widget Tests', () {
    testWidgets('renders station mode cards and toggles to Host mode',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = SettingsRepository(db);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            settingsRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: NetworkSettingsCard(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Multi-Register & LAN Database Sharing'), findsOneWidget);
      expect(find.text('Standalone'), findsOneWidget);
      expect(find.text('Main Host'), findsOneWidget);
      expect(find.text('Terminal Client'), findsOneWidget);

      // Tap Main Host station mode
      await tester.tap(find.text('Main Host'));
      await tester.pumpAndSettle();

      // Should now show host server settings
      expect(find.text('Server Port'), findsOneWidget);
      expect(find.text('Update Host'), findsOneWidget);

      // Tap Terminal Client mode
      await tester.tap(find.text('Terminal Client'));
      await tester.pumpAndSettle();

      expect(find.text('Host IP Address'), findsOneWidget);
      expect(find.text('Test Connection'), findsOneWidget);
      expect(find.text('Save & Connect'), findsOneWidget);
    });
  });
}
