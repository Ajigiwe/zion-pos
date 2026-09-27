import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/imports/data/import_repository.dart';
import 'package:instrument_pos/features/imports/domain/import_document.dart';
import 'package:instrument_pos/features/imports/presentation/import_file_service.dart';
import 'package:instrument_pos/features/imports/presentation/import_providers.dart';
import 'package:instrument_pos/features/imports/presentation/imports_page.dart';

import 'test_users.dart';

const _csv =
    'SKU,Product Name,Selling Price,Quantity\n'
    'GTR-001,Acoustic Guitar,320,5\n'
    'KEB-001,Keyboard,160,\n'; // row without quantity -> fails in stock modes

class _FakeFileService implements ImportFileService {
  bool templateSaved = false;

  @override
  Future<PickedImportFile?> pickFile() async =>
      PickedImportFile(name: 'january.csv', bytes: utf8.encode(_csv));

  @override
  Future<bool> saveTemplate() async {
    templateSaved = true;
    return true;
  }
}

class _FakeRepo implements BulkImportRepository {
  CommitResult? lastCommit;
  String? lastUserId;

  @override
  Future<ImportAnalysis> analyze({
    required ParsedImport document,
    required ImportMode mode,
  }) async {
    final issues = <RowIssue>[];
    for (final row in document.rows) {
      if (row.quantity == null && mode.touchesStock) {
        issues.add(
          RowIssue(
            rowNumber: row.rowNumber,
            identity: row.identity,
            message: 'Quantity is required in ${mode.label} mode.',
          ),
        );
      }
    }
    final issueRows = {for (final i in issues) i.rowNumber};
    return ImportAnalysis(
      mode: mode,
      totalRows: document.rows.length,
      validRows: document.rows.length - issueRows.length,
      issueCount: issues.length,
      issues: issues,
      problems: const [],
      newProducts: 2,
      existingProducts: 0,
      categoriesToCreate: 0,
      brandsToCreate: 0,
      unitsIn: mode == ImportMode.productOnly ? 0 : 5,
      unitsOut: 0,
      noChangeRows: 0,
    );
  }

  @override
  Future<CommitResult> commit({
    required ParsedImport document,
    required ImportAnalysis analysis,
    String? userId,
  }) async {
    lastCommit = CommitResult(
      batch: ImportBatch(
        id: 'b1',
        batchNumber: 'IMP-00001',
        importType: analysis.mode.importType,
        mode: analysis.mode.storageName,
        fileName: document.fileName,
        totalRows: analysis.totalRows,
        successfulRows: analysis.validRows,
        failedRows: analysis.issueCount == 0
            ? 0
            : analysis.totalRows - analysis.validRows,
        createdBy: userId,
        status: 'COMPLETED',
        createdAt: DateTime(2026, 3, 1),
      ),
      productsCreated: 1,
      productsUpdated: 1,
      movementsRecorded: 1,
      unitsIn: 5,
      unitsOut: 0,
    );
    lastUserId = userId;
    return lastCommit!;
  }

  @override
  Stream<List<ImportBatch>> watchBatches({int limit = 100}) async* {
    yield const [];
    yield [
      ImportBatch(
        id: 'b-old',
        batchNumber: 'IMP-00001',
        importType: 'BULK_STOCK',
        mode: 'addStock',
        fileName: 'previous.csv',
        totalRows: 10,
        successfulRows: 9,
        failedRows: 1,
        createdBy: 'u1',
        status: 'COMPLETED',
        createdAt: DateTime(2026, 1, 15),
      ),
    ];
  }
}

Widget _wrap({
  required String role,
  required _FakeRepo repo,
  required _FakeFileService files,
}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(
        testUser(id: 'u-manager', role: role),
      ),
      bulkImportRepositoryProvider.overrideWithValue(repo),
      importFileServiceProvider.overrideWithValue(files),
    ],
    child: const MaterialApp(home: Scaffold(body: ImportsPage())),
  );
}

void main() {
  testWidgets('cashier sees the lock notice and no import controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(role: 'CASHIER', repo: _FakeRepo(), files: _FakeFileService()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose file…'), findsNothing);
    expect(find.textContaining('Your role cannot import'), findsOneWidget);
  });

  testWidgets('manager picks a file, sees preview + errors and imports', (
    tester,
  ) async {
    // Tall viewport so the import history card below the fold is still built.
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _FakeRepo();
    final files = _FakeFileService();
    await tester.pumpWidget(_wrap(role: 'MANAGER', repo: repo, files: files));
    await tester.pumpAndSettle();

    expect(find.text('Import history'), findsOneWidget);
    expect(find.textContaining('previous.csv'), findsOneWidget); // history row

    await tester.tap(find.text('Choose file…'));
    await tester.pumpAndSettle();

    // Preview shows parsed counts and a row error for the blank quantity.
    expect(find.text('january.csv'), findsOneWidget);
    expect(find.text('Import 1 row(s)'), findsOneWidget);
    expect(find.textContaining('Quantity is required'), findsNothing);
    expect(find.text('View errors (1)'), findsOneWidget);

    await tester.tap(find.text('View errors (1)'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Quantity is required in Add stock mode.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import 1 row(s)'));
    await tester.pumpAndSettle();

    expect(repo.lastUserId, 'u-manager');
    expect(repo.lastCommit, isNotNull);
    expect(repo.lastCommit!.batch.batchNumber, 'IMP-00001');
    expect(find.textContaining('IMP-00001 imported'), findsOneWidget);
    // The panel resets after a successful commit.
    expect(find.text('Import 1 row(s)'), findsNothing);
  });

  testWidgets('template download writes through the file service', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final files = _FakeFileService();
    await tester.pumpWidget(
      _wrap(role: 'OWNER', repo: _FakeRepo(), files: files),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Download CSV template'));
    await tester.pumpAndSettle();
    expect(files.templateSaved, isTrue);
    expect(find.text('Template saved.'), findsOneWidget);
  });
}
