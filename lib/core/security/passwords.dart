import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Iterations for PBKDF2 — deliberately modest so local logins stay snappy;
/// raise before this code ever guards a server-side account.
const int kPbkdf2Iterations = 20000;

/// First-run account created when the users table is empty (§31 owner role).
const String kDefaultOwnerUsername = 'owner';
const String kDefaultOwnerPassword = 'admin123';

/// Hashes [password] with a random 16-byte salt unless [saltHex] is given.
/// Format: pbkdf2-sha256$iterations$saltHex$hashHex
String hashPassword(
  String password, {
  String? saltHex,
  int iterations = kPbkdf2Iterations,
}) {
  final salt = saltHex != null
      ? _decodeHex(saltHex)
      : List<int>.generate(16, (_) => Random.secure().nextInt(256));
  final derived = _pbkdf2(
    utf8.encode(password),
    salt,
    iterations,
    keyLength: 32,
  );
  return 'pbkdf2-sha256\$$iterations\$${_encodeHex(salt)}\$${_encodeHex(derived)}';
}

/// Returns true when [password] matches a stored [hashPassword] string.
bool verifyPassword(String password, String stored) {
  final parts = stored.split(r'$');
  if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
  final iterations = int.tryParse(parts[1]);
  final salt = _decodeHex(parts[2]);
  final expected = _decodeHex(parts[3]);
  if (iterations == null || salt.isEmpty || expected.isEmpty) return false;

  final actual = _pbkdf2(
    utf8.encode(password),
    salt,
    iterations,
    keyLength: expected.length,
  );
  if (actual.length != expected.length) return false;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual[i] ^ expected[i];
  }
  return diff == 0;
}

/// PBKDF2-HMAC-SHA256, standard construction with a big-endian block counter.
Uint8List _pbkdf2(
  List<int> password,
  List<int> salt,
  int iterations, {
  required int keyLength,
}) {
  final key = Uint8List(keyLength);
  final hmac = Hmac(sha256, password);
  var block = 1;
  var offset = 0;

  while (offset < keyLength) {
    final blockIndex = Uint8List(4)
      ..buffer.asByteData().setUint32(0, block, Endian.big);
    final u = hmac.convert([...salt, ...blockIndex]).bytes;
    final t = Uint8List.fromList(u);
    var previous = u;
    for (var i = 1; i < iterations; i++) {
      previous = hmac.convert(previous).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= previous[j];
      }
    }
    final take = min(keyLength - offset, t.length);
    key.setRange(offset, offset + take, t);
    offset += take;
    block += 1;
  }
  return key;
}

String _encodeHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _decodeHex(String hex) => [
  for (var i = 0; i + 1 < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];
