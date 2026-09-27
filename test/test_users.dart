import 'package:instrument_pos/core/database/app_database.dart';

/// Builds a generated users row for session overrides in widget tests.
User testUser({
  String id = 'u1',
  String role = 'OWNER',
  String displayName = 'Test User',
}) => User(
  id: id,
  username: displayName.toLowerCase().replaceAll(' ', '.'),
  displayName: displayName,
  passwordHash: 'unused-in-tests',
  role: role,
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  rev: 1, dirty: false,
);
