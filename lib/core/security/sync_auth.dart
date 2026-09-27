import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Default secret used when no pairing PIN is configured.
///
/// With no PIN the host accepts sync without checking a token, so this value
/// only keeps the request shape identical on both sides while the operator
/// decides whether to lock the LAN down with a PIN.
const _defaultSecret = 'instrument-pos-lan-v1';

String _secretFor(String pin) {
  final seed = pin.trim().isEmpty ? _defaultSecret : pin.trim();
  return sha256.convert(utf8.encode(seed)).toString();
}

/// Token a station sends with every sync request: an HMAC of the station id
/// under the shared pairing secret. Stateless — the host recomputes and
/// compares, so no session table is needed and a restart cannot lock
/// terminals out.
String syncToken({required String pin, required String stationId}) {
  final hmac = Hmac(sha256, utf8.encode(_secretFor(pin)));
  return hmac.convert(utf8.encode(stationId)).toString();
}

/// True when [token] proves the caller knows the pairing PIN for
/// [stationId].
bool verifySyncToken({
  required String pin,
  required String stationId,
  required String? token,
}) {
  if (stationId.isEmpty || token == null || token.isEmpty) return false;
  if (pin.trim().isEmpty) return false;
  return _constantTimeEquals(token, syncToken(pin: pin, stationId: stationId));
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
