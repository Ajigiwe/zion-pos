import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/security/passwords.dart';

void main() {
  test('hashed password verifies and rejects the wrong one', () {
    final stored = hashPassword('secret-123', iterations: 1000);
    expect(stored.startsWith('pbkdf2-sha256\$1000\$'), isTrue);
    expect(verifyPassword('secret-123', stored), isTrue);
    expect(verifyPassword('secret-124', stored), isFalse);
    expect(verifyPassword('', stored), isFalse);
  });

  test('same password produces different salts (no fixed hash)', () {
    final a = hashPassword('pw', iterations: 1000);
    final b = hashPassword('pw', iterations: 1000);
    expect(a, isNot(equals(b)));
    expect(verifyPassword('pw', a), isTrue);
    expect(verifyPassword('pw', b), isTrue);
  });

  test('garbage stored strings never verify', () {
    expect(verifyPassword('x', 'not-a-hash'), isFalse);
    expect(verifyPassword('x', 'pbkdf2-sha256\$bad\$00\$00'), isFalse);
  });
}
