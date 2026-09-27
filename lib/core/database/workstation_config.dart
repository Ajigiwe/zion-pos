import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class WorkstationConfig {
  const WorkstationConfig({
    this.mode = 'standalone',
    this.hostAddress = '',
    this.hostPort = 4242,
    this.securityPin = '',
    this.stationName = '',
    this.stationId = '',
    this.stationCode = '',
    this.lastRev = 0,
  });

  final String mode; // 'standalone', 'host', 'client'
  final String hostAddress;
  final int hostPort;
  final String securityPin;
  final String stationName;

  /// Stable identity of this installation. Regenerated only if the config
  /// file is lost — the host uses it to tell terminals apart across restarts.
  final String stationId;

  /// Short unique code baked into document numbers on client stations
  /// (`SA-K7F2-00001`) so two terminals can never issue the same receipt.
  final String stationCode;

  /// Highest host change sequence this station has applied. Client stations
  /// resume delta sync from here after a restart.
  final int lastRev;

  bool get isClient => mode == 'client';
  bool get isHost => mode == 'host';
  bool get isStandalone => mode == 'standalone';

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'hostAddress': hostAddress,
    'hostPort': hostPort,
    'securityPin': securityPin,
    'stationName': stationName,
    'stationId': stationId,
    'stationCode': stationCode,
    'lastRev': lastRev,
  };

  static WorkstationConfig fromJson(Map<String, dynamic> json) {
    return WorkstationConfig(
      mode: json['mode'] as String? ?? 'standalone',
      hostAddress: json['hostAddress'] as String? ?? '',
      hostPort: json['hostPort'] as int? ?? 4242,
      securityPin: json['securityPin'] as String? ?? '',
      stationName: json['stationName'] as String? ?? '',
      stationId: json['stationId'] as String? ?? '',
      stationCode: json['stationCode'] as String? ?? '',
      lastRev: json['lastRev'] as int? ?? 0,
    );
  }

  WorkstationConfig copyWith({
    String? mode,
    String? hostAddress,
    int? hostPort,
    String? securityPin,
    String? stationName,
    String? stationId,
    String? stationCode,
    int? lastRev,
  }) {
    return WorkstationConfig(
      mode: mode ?? this.mode,
      hostAddress: hostAddress ?? this.hostAddress,
      hostPort: hostPort ?? this.hostPort,
      securityPin: securityPin ?? this.securityPin,
      stationName: stationName ?? this.stationName,
      stationId: stationId ?? this.stationId,
      stationCode: stationCode ?? this.stationCode,
      lastRev: lastRev ?? this.lastRev,
    );
  }

  static WorkstationConfig _current = const WorkstationConfig();
  static WorkstationConfig get current => _current;

  /// Test hook: swaps the in-memory configuration without touching disk.
  @visibleForTesting
  static void setCurrentForTest(WorkstationConfig config) => _current = config;

  static File? _configFile;

  static Future<File> _getFile() async {
    if (_configFile != null) return _configFile!;
    try {
      final dir = await getApplicationSupportDirectory();
      final globalFile = File('${dir.path}${Platform.pathSeparator}workstation_config.json');
      _configFile = globalFile;
    } catch (_) {
      _configFile = File('workstation_config.json');
    }
    return _configFile!;
  }

  /// Loads the persisted workstation configuration from disk, minting a
  /// station identity the first time this PC runs the app.
  static Future<WorkstationConfig> load() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _current = fromJson(json);
        if (_current.stationId.isEmpty || _current.stationCode.isEmpty) {
          _current = _current.copyWith(
            stationId: const Uuid().v4(),
            stationCode: _randomCode(),
          );
          await _write(_current);
        }
        debugPrint(
          '[WorkstationConfig] mode=${_current.mode} '
          'host=${_current.hostAddress}:${_current.hostPort} '
          'station=${_current.stationCode}',
        );
        return _current;
      }
    } catch (e) {
      debugPrint('[WorkstationConfig] Error loading config: $e');
    }
    _current = WorkstationConfig(
      stationId: const Uuid().v4(),
      stationCode: _randomCode(),
    );
    await _write(_current);
    return _current;
  }

  /// Saves the workstation configuration to disk.
  ///
  /// Station identity and the sync cursor are owned by this class: settings
  /// forms pass a config without them, so they are carried over rather than
  /// wiped (a re-minted station id would look like a brand-new terminal to
  /// the host, and a zeroed cursor would replay the whole database).
  static Future<void> save(WorkstationConfig config) async {
    final merged = WorkstationConfig(
      mode: config.mode,
      hostAddress: config.hostAddress,
      hostPort: config.hostPort,
      securityPin: config.securityPin,
      stationName: config.stationName.isNotEmpty
          ? config.stationName
          : _current.stationName,
      stationId: config.stationId.isNotEmpty
          ? config.stationId
          : _current.stationId,
      stationCode: config.stationCode.isNotEmpty
          ? config.stationCode
          : _current.stationCode,
      lastRev: config.lastRev != 0 ? config.lastRev : _current.lastRev,
    );
    _current = merged;
    await _write(merged);
    debugPrint(
      '[WorkstationConfig] Saved config: mode=${merged.mode}, '
      'host=${merged.hostAddress}:${merged.hostPort}, '
      'station=${merged.stationCode}',
    );
  }

  /// Persists the sync cursor without touching any other setting. Written on
  /// every applied sync batch, so failures are swallowed.
  static Future<void> saveLastRev(int lastRev) async {
    if (lastRev == _current.lastRev) return;
    _current = _current.copyWith(lastRev: lastRev);
    await _write(_current);
  }

  static Future<void> _write(WorkstationConfig config) async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode(config.toJson()));
    } catch (e) {
      debugPrint('[WorkstationConfig] Error saving config: $e');
    }
  }

  /// Four unambiguous characters used inside document numbers.
  static String _randomCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final bytes = const Uuid().v4().replaceAll('-', '').substring(0, 8);
    final buffer = StringBuffer();
    for (var i = 0; i < 4; i++) {
      final code = bytes.codeUnitAt(i * 2) % alphabet.length;
      buffer.write(alphabet[code]);
    }
    return buffer.toString();
  }
}
