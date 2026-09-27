import 'package:flutter/foundation.dart';

enum NetworkStationMode {
  standalone,
  host,
  client;

  String get label {
    switch (this) {
      case NetworkStationMode.standalone:
        return 'Standalone (Single PC)';
      case NetworkStationMode.host:
        return 'Main Host Station (Server)';
      case NetworkStationMode.client:
        return 'Terminal Station (Client)';
    }
  }

  String get description {
    switch (this) {
      case NetworkStationMode.standalone:
        return 'Runs local database on this PC only.';
      case NetworkStationMode.host:
        return 'Hosts database for other POS registers in the store over LAN.';
      case NetworkStationMode.client:
        return 'Connects to a Main Host Station on your local network.';
    }
  }

  static NetworkStationMode fromString(String? val) {
    if (val == 'host') return NetworkStationMode.host;
    if (val == 'client') return NetworkStationMode.client;
    return NetworkStationMode.standalone;
  }
}

@immutable
class NetworkSettings {
  const NetworkSettings({
    this.mode = NetworkStationMode.standalone,
    this.hostPort = 4242,
    this.remoteHostAddress = '',
    this.remoteHostPort = 4242,
    this.securityPin = '',
  });

  final NetworkStationMode mode;
  final int hostPort;
  final String remoteHostAddress;
  final int remoteHostPort;
  final String securityPin;

  bool get isStandalone => mode == NetworkStationMode.standalone;
  bool get isHost => mode == NetworkStationMode.host;
  bool get isClient => mode == NetworkStationMode.client;

  NetworkSettings copyWith({
    NetworkStationMode? mode,
    int? hostPort,
    String? remoteHostAddress,
    int? remoteHostPort,
    String? securityPin,
  }) {
    return NetworkSettings(
      mode: mode ?? this.mode,
      hostPort: hostPort ?? this.hostPort,
      remoteHostAddress: remoteHostAddress ?? this.remoteHostAddress,
      remoteHostPort: remoteHostPort ?? this.remoteHostPort,
      securityPin: securityPin ?? this.securityPin,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkSettings &&
          runtimeType == other.runtimeType &&
          mode == other.mode &&
          hostPort == other.hostPort &&
          remoteHostAddress == other.remoteHostAddress &&
          remoteHostPort == other.remoteHostPort &&
          securityPin == other.securityPin;

  @override
  int get hashCode => Object.hash(
    mode,
    hostPort,
    remoteHostAddress,
    remoteHostPort,
    securityPin,
  );

  @override
  String toString() =>
      'NetworkSettings(mode: $mode, hostPort: $hostPort, remoteHostAddress: $remoteHostAddress, remoteHostPort: $remoteHostPort)';
}

abstract class NetworkSettingKeys {
  static const stationMode = 'network.stationMode';
  static const hostPort = 'network.hostPort';
  static const remoteHostAddress = 'network.remoteHostAddress';
  static const remoteHostPort = 'network.remoteHostPort';
  static const securityPin = 'network.securityPin';

  static const allKeys = [
    stationMode,
    hostPort,
    remoteHostAddress,
    remoteHostPort,
    securityPin,
  ];
}
