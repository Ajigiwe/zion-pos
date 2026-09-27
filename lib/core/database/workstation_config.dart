import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class WorkstationConfig {
  const WorkstationConfig({
    this.mode = 'standalone',
    this.hostAddress = '',
    this.hostPort = 4242,
    this.securityPin = '',
    this.stationName = '',
  });

  final String mode; // 'standalone', 'host', 'client'
  final String hostAddress;
  final int hostPort;
  final String securityPin;
  final String stationName;

  bool get isClient => mode == 'client';
  bool get isHost => mode == 'host';
  bool get isStandalone => mode == 'standalone';

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'hostAddress': hostAddress,
    'hostPort': hostPort,
    'securityPin': securityPin,
    'stationName': stationName,
  };

  static WorkstationConfig fromJson(Map<String, dynamic> json) {
    return WorkstationConfig(
      mode: json['mode'] as String? ?? 'standalone',
      hostAddress: json['hostAddress'] as String? ?? '',
      hostPort: json['hostPort'] as int? ?? 4242,
      securityPin: json['securityPin'] as String? ?? '',
      stationName: json['stationName'] as String? ?? '',
    );
  }

  static WorkstationConfig _current = const WorkstationConfig();
  static WorkstationConfig get current => _current;

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

  /// Loads the persisted workstation configuration from disk.
  static Future<WorkstationConfig> load() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _current = fromJson(json);
        debugPrint('[WorkstationConfig] Loaded config: mode=${_current.mode}, host=${_current.hostAddress}:${_current.hostPort}');
        return _current;
      }
    } catch (e) {
      debugPrint('[WorkstationConfig] Error loading config: $e');
    }
    _current = const WorkstationConfig();
    return _current;
  }

  /// Saves the workstation configuration to disk.
  static Future<void> save(WorkstationConfig config) async {
    _current = config;
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode(config.toJson()));
      debugPrint('[WorkstationConfig] Saved config: mode=${config.mode}, host=${config.hostAddress}:${config.hostPort}');
    } catch (e) {
      debugPrint('[WorkstationConfig] Error saving config: $e');
    }
  }
}
