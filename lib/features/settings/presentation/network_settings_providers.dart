import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/core/database/lan_database_server.dart';
import 'package:instrument_pos/core/database/lan_sync_service.dart';
import 'package:instrument_pos/core/database/workstation_config.dart';
import 'package:instrument_pos/features/settings/domain/network_settings.dart';

/// Provider for the singleton LAN server instance.
final lanDatabaseServerProvider = Provider<LanDatabaseServer>((ref) {
  final db = ref.watch(databaseProvider);
  final server = LanDatabaseServer(db);
  ref.onDispose(server.stop);
  return server;
});

/// Future provider discovering the current PC's local network IPv4 addresses.
final localIpAddressesProvider = FutureProvider<List<String>>((ref) async {
  return LanDatabaseServer.getLocalIpAddresses();
});

/// Manages reactive station mode and LAN hosting configuration.
class NetworkSettingsController extends Notifier<NetworkSettings> {
  @override
  NetworkSettings build() {
    final cfg = WorkstationConfig.current;
    final mode = NetworkStationMode.values.firstWhere(
      (m) => m.name == cfg.mode,
      orElse: () => NetworkStationMode.standalone,
    );
    final settings = NetworkSettings(
      mode: mode,
      hostPort: cfg.hostPort,
      remoteHostAddress: cfg.hostAddress,
      remoteHostPort: cfg.hostPort,
      securityPin: cfg.securityPin,
    );
    if (settings.isHost) {
      Future.microtask(() => _syncServerWithMode(settings));
    }
    return settings;
  }

  Future<void> loadFromDb() async {
    final cfg = WorkstationConfig.current;
    final mode = NetworkStationMode.values.firstWhere(
      (m) => m.name == cfg.mode,
      orElse: () => NetworkStationMode.standalone,
    );
    final settings = NetworkSettings(
      mode: mode,
      hostPort: cfg.hostPort,
      remoteHostAddress: cfg.hostAddress,
      remoteHostPort: cfg.hostPort,
      securityPin: cfg.securityPin,
    );
    state = settings;
    await _syncServerWithMode(settings);
  }

  Future<void> _syncServerWithMode(NetworkSettings settings) async {
    // The sync triggers read the station role to decide whether local edits
    // advance the change sequence; keep them in step with the UI mode.
    await ref.read(databaseProvider).updateSyncRole(settings.mode.name);

    final server = ref.read(lanDatabaseServerProvider);
    if (settings.isHost) {
      await server.startRetrying(
        port: settings.hostPort,
        securityPin: settings.securityPin,
      );
    } else if (server.isRunning || server.isRetrying) {
      await server.stop();
    }
    await ref.read(lanSyncServiceProvider).restart();
  }

  Future<void> setMode(
    NetworkStationMode mode, {
    required String actingUserId,
  }) async {
    final updated = state.copyWith(mode: mode);
    state = updated;
    await WorkstationConfig.save(WorkstationConfig(
      mode: mode.name,
      hostAddress: updated.remoteHostAddress,
      hostPort: updated.remoteHostPort,
      securityPin: updated.securityPin,
    ));
    await _syncServerWithMode(updated);
  }

  Future<void> updateHostConfig({
    required int port,
    required String securityPin,
    required String actingUserId,
  }) async {
    final updated = state.copyWith(
      hostPort: port,
      securityPin: securityPin,
    );
    state = updated;
    await WorkstationConfig.save(WorkstationConfig(
      mode: 'host',
      hostPort: port,
      securityPin: securityPin,
    ));
    final server = ref.read(lanDatabaseServerProvider);
    await server.stop();
    await _syncServerWithMode(updated);
  }

  Future<void> updateClientConfig({
    required String hostAddress,
    required int port,
    required String securityPin,
    required String actingUserId,
  }) async {
    final updated = state.copyWith(
      mode: NetworkStationMode.client,
      remoteHostAddress: hostAddress,
      remoteHostPort: port,
      securityPin: securityPin,
    );
    state = updated;
    await WorkstationConfig.save(WorkstationConfig(
      mode: 'client',
      hostAddress: hostAddress,
      hostPort: port,
      securityPin: securityPin,
    ));
    await _syncServerWithMode(updated);
  }
}

final networkSettingsControllerProvider =
    NotifierProvider<NetworkSettingsController, NetworkSettings>(
      NetworkSettingsController.new,
    );
