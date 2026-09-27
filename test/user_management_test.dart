import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';
import 'package:instrument_pos/features/audit/presentation/audit_providers.dart';
import 'package:instrument_pos/features/auth/data/auth_repository.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/auth/presentation/user_management_page.dart';
import 'package:instrument_pos/features/auth/presentation/user_providers.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';

import 'test_users.dart';

void main() {
  Widget wrap(User current) => ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(current),
      auditLogsProvider.overrideWith(
        (ref) => Stream.value(const <AuditEntry>[]),
      ),
      usersProvider.overrideWith(
        (ref) => Stream.value([
          testUser(id: 'u1', role: 'OWNER', displayName: 'Owner'),
          testUser(id: 'u2', role: 'CASHIER', displayName: 'Ama'),
        ]),
      ),
      lowStockThresholdProvider.overrideWith((ref) async => 5),
    ],
    child: const MaterialApp(home: Scaffold(body: SettingsPage())),
  );

  testWidgets('owner can add users and sees the account list', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(testUser(id: 'u1')));
    await tester.pumpAndSettle();

    expect(find.text('Add user'), findsOneWidget);
    expect(find.text('Owner'), findsWidgets);
    expect(find.text('Ama'), findsOneWidget);
    expect(find.text('Cashier'), findsWidgets);
    // Owners also see the read-only audit log section.
    expect(find.text('Audit log'), findsOneWidget);
    expect(find.text('No activity recorded yet.'), findsOneWidget);
  });

  testWidgets('cashier sees only the lock notice, no controls', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(testUser(id: 'u2', role: 'CASHIER')));
    await tester.pumpAndSettle();

    expect(find.text('Add user'), findsNothing);
    expect(find.text('Audit log'), findsNothing);
    expect(
      find.text('Only owners and admins can manage users.'),
      findsOneWidget,
    );
  });

  testWidgets('cashiers and managers can access Network & Registers tab to connect to host', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(testUser(id: 'u2', role: 'CASHIER')));
    await tester.pumpAndSettle();

    expect(find.text('Network & Registers'), findsOneWidget);
    await tester.tap(find.text('Network & Registers'));
    await tester.pumpAndSettle();

    expect(find.text('Multi-Register & LAN Database Sharing'), findsOneWidget);
    expect(find.text('Terminal Client'), findsOneWidget);
  });

  testWidgets('my-account card and roles reference document every role', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(testUser(id: 'u1', displayName: 'Owner')));
    await tester.pumpAndSettle();

    // My-account card.
    expect(find.text('Signed in as Owner'), findsOneWidget);
    expect(find.text('@owner · Owner'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);

    // Roles & permissions reference lists every role and its description
    // (below the owner-only cards, so scroll it into view first).
    await tester.scrollUntilVisible(
      find.text('Roles & permissions'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Roles & permissions'), findsOneWidget);
    expect(find.text('Inventory Manager'), findsOneWidget);
    expect(
      find.text(
        'Makes sales and exchanges at the register — no refunds or '
        'stock edits.',
      ),
      findsOneWidget,
    );
    // Permission chips for a role are rendered.
    expect(find.text('Manage users'), findsWidgets);
    expect(find.text('Make sales'), findsWidgets);
  });

  testWidgets(
    'password change flow surfaces wrong-current errors and succeeds',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _ChangePasswordFake();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(testUser(id: 'u1')),
            auditLogsProvider.overrideWith(
              (ref) => Stream.value(const <AuditEntry>[]),
            ),
            usersProvider.overrideWith(
              (ref) => Stream.value(<User>[testUser(id: 'u1')]),
            ),
            authRepositoryProvider.overrideWithValue(repo),
            lowStockThresholdProvider.overrideWith((ref) async => 5),
          ],
          child: const MaterialApp(home: Scaffold(body: SettingsPage())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Change password'));
      await tester.pumpAndSettle();
      expect(find.text('Current password'), findsOneWidget);

      // Wrong current password shows the repository error inline.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current password'),
        'wrong',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'),
        'newpass123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'newpass123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
      expect(find.text('Current password is incorrect.'), findsOneWidget);
      expect(repo.lastCall, isNull);

      // Correct current password closes the dialog with a confirmation.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current password'),
        'admin123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
      expect(find.text('Current password is incorrect.'), findsNothing);
      expect(repo.lastCall, (userId: 'u1', newPassword: 'newpass123'));
      expect(find.text('Password changed.'), findsOneWidget);
    },
  );
}

class _ChangePasswordFake implements AuthRepository {
  /// The only current password this fake accepts.
  final String acceptedCurrent = 'admin123';
  ({String userId, String newPassword})? lastCall;

  @override
  Future<User> authenticate(String username, String password) async {
    throw UnimplementedError();
  }

  @override
  Stream<List<User>> watchUsers() => const Stream.empty();

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
  }) async {
    if (currentPassword != acceptedCurrent) {
      throw AuthException('Current password is incorrect.');
    }
    lastCall = (userId: userId, newPassword: newPassword);
  }
}
