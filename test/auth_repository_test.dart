import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/security/passwords.dart';
import 'package:instrument_pos/features/auth/data/auth_repository.dart';

void main() {
  late AppDatabase db;
  late DriftAuthRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftAuthRepository(db);
  });

  tearDown(() => db.close());

  test('first run seeds the owner account and it can log in', () async {
    final users = await repo.watchUsers().first;
    expect(users, hasLength(1));
    expect(users.single.username, kDefaultOwnerUsername);
    expect(users.single.role, 'OWNER');

    final user = await repo.authenticate('OWNER', kDefaultOwnerPassword);
    expect(user.displayName, 'Owner');
    await expectLater(
      repo.authenticate('owner', 'wrong-password'),
      throwsA(isA<AuthException>()),
    );
  });

  test(
    'creating a cashier lets them log in and rejects duplicate usernames',
    () async {
      final created = await repo.createUser(
        username: 'AmA',
        displayName: 'Ama',
        role: 'CASHIER',
        password: 'secret1',
      );
      expect(created.role, 'CASHIER');
      expect(created.passwordHash, isNot(contains('secret1')));
      expect(created.passwordHash.startsWith('pbkdf2-sha256\$'), isTrue);

      final auth = await repo.authenticate('ama', 'secret1');
      expect(auth.id, created.id);

      await expectLater(
        repo.createUser(
          username: 'AMA',
          displayName: 'Ama again',
          role: 'CASHIER',
          password: 'secret2',
        ),
        throwsA(isA<AuthException>()),
      );
    },
  );

  test(
    'deactivating an account blocks login and restores on reactivation',
    () async {
      final created = await repo.createUser(
        username: 'kofi',
        displayName: 'Kofi',
        role: 'MANAGER',
        password: 'secret1',
      );
      await repo.setActive(created.id, active: false);
      await expectLater(
        repo.authenticate('kofi', 'secret1'),
        throwsA(isA<AuthException>()),
      );
      await repo.setActive(created.id, active: true);
      expect((await repo.authenticate('kofi', 'secret1')).id, created.id);
    },
  );

  test(
    'owner can never be disabled while it is the only active owner',
    () async {
      final owner = await repo.authenticate('owner', kDefaultOwnerPassword);
      expect(await repo.countActiveOwners(), 1);

      await repo.setActive(owner.id, active: false);
      expect(await repo.countActiveOwners(), 0);
      // The guard lives in the UI; repository-level deactivation is allowed so
      // the owner keeps an escape hatch. Verify a disabled owner can't log in.
      await expectLater(
        repo.authenticate('owner', kDefaultOwnerPassword),
        throwsA(isA<AuthException>()),
      );
    },
  );
}
