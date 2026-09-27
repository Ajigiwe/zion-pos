import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/features/imports/data/import_repository.dart';
import 'package:instrument_pos/features/imports/presentation/import_file_service.dart';

final bulkImportRepositoryProvider = Provider<BulkImportRepository>((ref) {
  return DriftBulkImportRepository(ref.watch(databaseProvider));
});

/// Live list of committed import batches, newest first (§20).
final importBatchesProvider = StreamProvider.autoDispose<List<ImportBatch>>(
  (ref) => ref.watch(bulkImportRepositoryProvider).watchBatches(),
);

/// File picking / template saving, injected so widget tests can fake it.
final importFileServiceProvider = Provider<ImportFileService>((ref) {
  return DesktopImportFileService();
});
