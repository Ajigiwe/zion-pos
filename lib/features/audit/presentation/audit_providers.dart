import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/features/audit/data/audit_repository.dart';

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  return AuditRepository(ref.watch(databaseProvider));
});

/// Newest audit entries for the read-only owner/admin view.
final auditLogsProvider = StreamProvider<List<AuditEntry>>((ref) {
  return ref.watch(auditRepositoryProvider).watchRecent();
});
