import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/core/database/lan_database_server.dart';
import 'package:instrument_pos/core/database/lan_sync_service.dart';
import 'package:instrument_pos/core/database/sync_schema.dart';
import 'package:instrument_pos/core/database/workstation_config.dart';
import 'package:instrument_pos/core/numbering/document_numbers.dart';

/// flutter_test swaps in an HttpClient that answers every request with 400.
/// These tests talk to a real socket on the loopback interface, so opt out by
/// restoring the real client factory from the base class.
class _LoopbackHttpOverrides extends HttpOverrides {
  @override
  // ignore: unnecessary_overrides - super is what builds a real client here
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _LoopbackHttpOverrides();
  // The host and the client are deliberately two databases on one executor.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tearDown(() {
    WorkstationConfig.setCurrentForTest(const WorkstationConfig());
  });

  group('change sequence triggers', () {
    test('a new local row is dirty and takes the next revision', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.updateSyncRole('client');

      await db
          .into(db.categories)
          .insert(CategoriesCompanion.insert(id: 'c1', name: 'Jazz Guitars'));

      final meta = await readSyncRowMeta(db, 'categories', 'c1');
      expect(meta, isNotNull);
      expect(meta!.dirty, isTrue);
      expect(meta.rev, greaterThan(1));
    });

    test('host edits advance the revision, client edits only mark dirty',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.updateSyncRole('host');
      await db
          .into(db.categories)
          .insert(CategoriesCompanion.insert(id: 'c1', name: 'Studio Drums'));

      final hostEdit = db.update(db.categories)
        ..where((t) => t.id.equals('c1'));
      await hostEdit
          .write(const CategoriesCompanion(name: Value('Studio Drums & Percussion')));
      final afterHostEdit = (await readSyncRowMeta(db, 'categories', 'c1'))!;

      await db.updateSyncRole('client');
      final clientEdit = db.update(db.categories)
        ..where((t) => t.id.equals('c1'));
      await clientEdit.write(const CategoriesCompanion(name: Value('Studio Drums')));
      final afterClientEdit = (await readSyncRowMeta(db, 'categories', 'c1'))!;

      expect(afterHostEdit.rev, greaterThan(1));
      expect(afterClientEdit.rev, afterHostEdit.rev,
          reason: 'a client edit must not renumber a host row');
      expect(afterClientEdit.dirty, isTrue);
    });

    test('writeSyncRow stamps host data without firing the triggers',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.updateSyncRole('client');
      final before = await currentRev(db);

      await writeSyncRow(
        db,
        table: 'categories',
        info: syncTableInfos(db)['categories']!,
        row: CategoriesCompanion.insert(
          id: 'host-1',
          name: 'House Amps',
          rev: const Value(42),
          dirty: const Value(false),
        ),
        entityId: 'host-1',
        rev: 42,
        dirty: false,
      );

      final meta = await readSyncRowMeta(db, 'categories', 'host-1');
      expect(meta!.rev, 42);
      expect(meta.dirty, isFalse);
      expect(await currentRev(db), before,
          reason: 'replicated rows must not consume a local revision');
    });
  });

  group('document numbering', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
    });
    tearDown(() => db.close());

    Future<void> addSale(String id, String receipt) => db
        .into(db.sales)
        .insert(SalesCompanion.insert(
          id: id,
          receiptNumber: receipt,
          subtotal: 10,
          total: 10,
        ));

    test('host and standalone stations keep the classic SA-##### shape',
        () async {
      final first = await nextDocumentNumber(
        db,
        table: 'sales',
        column: 'receipt_number',
        prefix: 'SA',
      );
      expect(first, 'SA-00001');
      await addSale('s1', first);
      final second = await nextDocumentNumber(
        db,
        table: 'sales',
        column: 'receipt_number',
        prefix: 'SA',
      );
      expect(second, 'SA-00002');
    });

    test('client stations never pick a number another terminal issued',
        () async {
      WorkstationConfig.setCurrentForTest(
        const WorkstationConfig(mode: 'client', stationCode: 'K7F2'),
      );
      // A receipt written by the host (or restored from a backup).
      await addSale('host-sale', 'SA-00001');

      final first = await nextDocumentNumber(
        db,
        table: 'sales',
        column: 'receipt_number',
        prefix: 'SA',
      );
      expect(first, 'SA-K7F2-00001');
      await addSale('client-sale', first);

      final second = await nextDocumentNumber(
        db,
        table: 'sales',
        column: 'receipt_number',
        prefix: 'SA',
      );
      expect(second, 'SA-K7F2-00002');
    });

    test('rejects a misspelled column instead of returning a constant',
        () async {
      expect(
        () => nextDocumentNumber(
          db,
          table: 'sales',
          column: 'receiptNumber',
          prefix: 'SA',
        ),
        throwsArgumentError,
      );
    });
  });

  group('host/client loopback sync', () {
    late AppDatabase hostDb;
    late AppDatabase clientDb;
    LanDatabaseServer? server;

    Future<void> startServer({String? pin}) async {
      final started = LanDatabaseServer(hostDb);
      await started.start(port: 0, securityPin: pin);
      server = started;
    }

    setUp(() async {
      hostDb = AppDatabase(NativeDatabase.memory());
      await hostDb.updateSyncRole('host');
      clientDb = AppDatabase(NativeDatabase.memory());
      await clientDb.updateSyncRole('client');
    });

    tearDown(() async {
      await server?.stop();
      server = null;
      await hostDb.close();
      await clientDb.close();
    });

    /// Points the workstation at the running server and builds the client
    /// sync service against [clientDb].
    Future<LanSyncService> connect({String pin = '4242'}) async {
      final running = server;
      if (running == null) {
        throw StateError('start the server before connecting');
      }
      WorkstationConfig.setCurrentForTest(
        WorkstationConfig(
          mode: 'client',
          hostAddress: '127.0.0.1',
          hostPort: running.port,
          securityPin: pin,
          stationId: 'station-client-1',
          stationCode: 'K7F2',
          stationName: 'Till 2',
        ),
      );
      return LanSyncService(clientDb);
    }

    test('sync refuses to run without a pairing PIN on the host', () async {
      await startServer(pin: '');
      final service = await connect(pin: '');
      await service.syncNow();

      expect(service.isOnlineNotifier.value, isFalse);
      expect(service.statusNotifier.value, contains('PIN'));
    });

    test('sync refuses a token built from the wrong PIN', () async {
      await startServer(pin: '4242');
      final service = await connect(pin: '0000');
      await service.syncNow();

      expect(service.isOnlineNotifier.value, isFalse);
      expect(service.statusNotifier.value, contains('PIN'));
    });

    test('host unreachable backs off instead of hanging', () async {
      await startServer(pin: '4242');
      final service = await connect();
      await server?.stop();

      await service.syncNow();

      expect(service.isOnlineNotifier.value, isFalse);
      expect(service.statusNotifier.value, contains('unreachable'));
    });

    test('client pushes a sale, pulls catalog edits and never duplicates',
        () async {
      await startServer(pin: '4242');
      final service = await connect();

      // Host owns this category.
      await hostDb
          .into(hostDb.categories)
          .insert(CategoriesCompanion.insert(id: 'host-cat', name: 'Amps'));

      // Client rings up a sale while the host is away.
      final receipt = await nextDocumentNumber(
        clientDb,
        table: 'sales',
        column: 'receipt_number',
        prefix: 'SA',
      );
      expect(receipt, 'SA-K7F2-00001');
      await clientDb.into(clientDb.sales).insert(
            SalesCompanion.insert(
              id: 'sale-1',
              receiptNumber: receipt,
              subtotal: 250,
              total: 250,
              isSynced: const Value(false),
            ),
          );

      await service.syncNow();

      final hostSales = await hostDb.select(hostDb.sales).get();
      expect(hostSales, hasLength(1));
      expect(hostSales.single.id, 'sale-1');
      expect(hostSales.single.receiptNumber, 'SA-K7F2-00001');
      expect(hostSales.single.dirty, isFalse,
          reason: 'the host stores replicated rows as clean');
      expect(hostSales.single.rev, greaterThan(1));

      final pushed = await (clientDb.select(clientDb.sales)
            ..where((s) => s.id.equals('sale-1')))
          .getSingle();
      expect(pushed.dirty, isFalse, reason: 'acknowledged rows stop pushing');
      expect(pushed.isSynced, isTrue);

      // Catalog travelled the other way.
      final categories = await clientDb.select(clientDb.categories).get();
      expect(categories.map((c) => c.id), contains('host-cat'));

      // The host edits a category; the client sees it next cycle.
      final hostEdit = hostDb.update(hostDb.categories)
        ..where((t) => t.id.equals('host-cat'));
      await hostEdit.write(const CategoriesCompanion(name: Value('Amps & Cabs')));
      await service.syncNow();

      final edited = await (clientDb.select(clientDb.categories)
            ..where((t) => t.id.equals('host-cat')))
          .getSingle();
      expect(edited.name, 'Amps & Cabs');
      expect(edited.dirty, isFalse);
      expect(edited.rev, greaterThan(1));

      // Forcing the same row dirty again must not create a second sale.
      await clientDb.customStatement(
        'UPDATE sales SET dirty = 1 WHERE id = ?',
        ['sale-1'],
      );
      await service.syncNow();
      expect(await hostDb.select(hostDb.sales).get(), hasLength(1));
      final resent = await (clientDb.select(clientDb.sales)
            ..where((s) => s.id.equals('sale-1')))
          .getSingle();
      expect(resent.dirty, isFalse);
    });

    test('a local edit reaches the host instead of being pulled over',
        () async {
      await startServer(pin: '4242');

      await hostDb
          .into(hostDb.categories)
          .insert(CategoriesCompanion.insert(id: 'shared', name: 'Patch Cables'));
      final service = await connect();
      await service.syncNow();

      final pulled = await (clientDb.select(clientDb.categories)
            ..where((t) => t.id.equals('shared')))
          .getSingle();
      expect(pulled.name, 'Patch Cables');
      expect(pulled.dirty, isFalse, reason: 'replicated rows arrive clean');

      // The client renames it locally while the host keeps still...
      final localRename = clientDb.update(clientDb.categories)
        ..where((t) => t.id.equals('shared'));
      await localRename
          .write(const CategoriesCompanion(name: Value('Cables & Leads')));

      await service.syncNow();

      final local = await (clientDb.select(clientDb.categories)
            ..where((t) => t.id.equals('shared')))
          .getSingle();
      expect(local.name, 'Cables & Leads',
          reason: 'the pending local edit must reach the host first');
      expect(local.dirty, isFalse, reason: 'and is acknowledged');

      final hostRow = await (hostDb.select(hostDb.categories)
            ..where((t) => t.id.equals('shared')))
          .getSingle();
      expect(hostRow.name, 'Cables & Leads');

      // The host edits it later; the next pull brings the change back.
      final hostEdit = hostDb.update(hostDb.categories)
        ..where((t) => t.id.equals('shared'));
      await hostEdit
          .write(const CategoriesCompanion(name: Value('Cable Accessories')));
      await service.syncNow();

      final edited = await (clientDb.select(clientDb.categories)
            ..where((t) => t.id.equals('shared')))
          .getSingle();
      expect(edited.name, 'Cable Accessories');
      expect(edited.dirty, isFalse);
    });

    test('a stale local edit loses to the host and stops pushing', () async {
      await startServer(pin: '4242');

      await hostDb
          .into(hostDb.categories)
          .insert(CategoriesCompanion.insert(id: 'shared', name: 'Patch Cables'));
      final service = await connect();
      await service.syncNow();

      // Both ends rename the row while they are apart. The host's version is
      // the one every other terminal already trusts, so it wins honestly.
      final localRename = clientDb.update(clientDb.categories)
        ..where((t) => t.id.equals('shared'));
      await localRename
          .write(const CategoriesCompanion(name: Value('Cables & Leads')));
      final hostRename = hostDb.update(hostDb.categories)
        ..where((t) => t.id.equals('shared'));
      await hostRename
          .write(const CategoriesCompanion(name: Value('Cable Accessories')));

      await service.syncNow();

      final resolved = await (clientDb.select(clientDb.categories)
            ..where((t) => t.id.equals('shared')))
          .getSingle();
      expect(resolved.name, 'Cable Accessories');
      expect(resolved.dirty, isFalse, reason: 'the conflict is settled');

      // Another cycle must not drag the client's lost edit back to the host.
      await service.syncNow();
      final hostRow = await (hostDb.select(hostDb.categories)
            ..where((t) => t.id.equals('shared')))
          .getSingle();
      expect(hostRow.name, 'Cable Accessories');
      // The host keeps its own rows dirty on purpose: that flag is what would
      // push them if this station were ever reconfigured as a client.
      final stillPending = await (clientDb.select(clientDb.categories)
            ..where((t) => t.id.equals('shared')))
          .getSingle();
      expect(stillPending.dirty, isFalse);
    });

    test('two client terminals never issue the same receipt number',
        () async {
      await startServer(pin: '4242');

      // Numbers are scoped by station, so read them before the workstation
      // config is switched to client mode for this test.
      final hostReceipt = await nextDocumentNumber(
        hostDb,
        table: 'sales',
        column: 'receipt_number',
        prefix: 'SA',
      );
      expect(hostReceipt, 'SA-00001');

      final service = await connect();
      final clientReceipt = await nextDocumentNumber(
        clientDb,
        table: 'sales',
        column: 'receipt_number',
        prefix: 'SA',
      );
      expect(clientReceipt, 'SA-K7F2-00001');
      expect(clientReceipt, isNot(hostReceipt));

      await hostDb.into(hostDb.sales).insert(
            SalesCompanion.insert(
              id: 'host-sale',
              receiptNumber: hostReceipt,
              subtotal: 10,
              total: 10,
            ),
          );
      await clientDb.into(clientDb.sales).insert(
            SalesCompanion.insert(
              id: 'client-sale',
              receiptNumber: clientReceipt,
              subtotal: 20,
              total: 20,
            ),
          );

      await service.syncNow();

      final receipts = (await hostDb.select(hostDb.sales).get())
          .map((s) => s.receiptNumber)
          .toSet();
      expect(receipts, {'SA-00001', 'SA-K7F2-00001'});
    });
  });
}
