import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/app_root.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/auth/data/auth_repository.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/dashboard/presentation/dashboard_providers.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';
import 'package:instrument_pos/features/sales/presentation/sales_providers.dart';

import 'test_users.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.username = 'owner', this.password = 'admin123'});

  final String username;
  final String password;

  @override
  Future<User> authenticate(String username, String password) async {
    if (username.trim().toLowerCase() == this.username &&
        password == this.password) {
      return testUser(id: 'u-owner', role: 'OWNER', displayName: 'Owner');
    }
    throw AuthException('Invalid username or password.');
  }

  @override
  Stream<List<User>> watchUsers() => Stream.value([testUser()]);

  @override
  Future<User> createUser({
    required String username,
    required String displayName,
    required String role,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> setActive(
    String userId, {
    required bool active,
    String? actingUserId,
  }) async {}

  @override
  Future<int> countActiveOwners() async => 1;

  @override
  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {}
}

void main() {
  testWidgets('wrong credentials show an error and stay on the login page', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(username: 'owner', password: 'admin123'),
          ),
        ],
        child: const MaterialApp(home: AppRoot()),
      ),
    );
    await tester.pump();

    expect(find.text(kStoreInfo.name), findsOneWidget);
    expect(find.textContaining('Sign in to open the register'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'owner');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'wrong');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Invalid username or password.'), findsOneWidget);
    expect(find.textContaining('Sign in to open the register'), findsOneWidget);
  });

  testWidgets('valid credentials open the shell', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(username: 'owner', password: 'admin123'),
          ),
          // The shell now lands on the Sales page; keep its DB-backed streams
          // out of the widget test.
          productsProvider.overrideWith(
            (ref, query) => Stream.value(const <ProductWithStock>[]),
          ),
          recentSalesProvider.overrideWith(
            (ref) => Stream.value(const <Sale>[]),
          ),
          lowStockCountProvider.overrideWith((ref) => Stream.value(0)),
        ],
        child: const MaterialApp(home: AppRoot()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'owner');
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'admin123',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The shell opens straight on the Sales page (the till), not the
    // dashboard placeholder.
    expect(find.textContaining('Cart is empty'), findsOneWidget);
    expect(find.text('Coming in a later phase'), findsNothing);
    expect(find.text('Sign in to open the register'), findsNothing);
    expect(find.text('Owner'), findsWidgets); // user footer in the sidebar
  });
}
