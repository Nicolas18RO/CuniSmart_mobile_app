import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/domain/genealogy/parent_link.dart';
import 'package:frontend/features/r3/application/r3_local_persistence.dart';
import 'package:frontend/features/r3/data/r3_local_store.dart';
import 'package:frontend/models/rabbit.dart';
import 'package:frontend/models/sync_operation.dart';
import 'package:frontend/models/sync_status.dart';
import 'package:frontend/services/connectivity_gate.dart';
import 'package:frontend/services/rabbit_local_store.dart';
import 'package:frontend/services/sync_engine.dart';
import 'package:http/testing.dart';

const child = '00000000-0000-4000-8000-000000000001';
const father = '00000000-0000-4000-8000-000000000002';
const mother = '00000000-0000-4000-8000-000000000003';
const secondFather = '00000000-0000-4000-8000-000000000004';
const other = '00000000-0000-4000-8000-000000000005';

Rabbit animal(String uuid,
        {String sex = 'male',
        int owner = 1,
        String knowledge = 'UNKNOWN',
        RabbitSyncStatus syncStatus = RabbitSyncStatus.synced}) =>
    Rabbit(
        id: 1,
        userId: owner,
        uuid: uuid,
        name: uuid,
        breed: 'rex',
        sex: sex,
        birthDate: '2024-01-01',
        status: 'active',
        notes: '',
        version: 1,
        genealogyKnowledge: knowledge,
        createdAt: '2025-01-01',
        updatedAt: '2025-01-01',
        syncStatus: syncStatus);

R3LocalPersistence service(AppDatabase db,
        {int owner = 1, bool Function()? current}) =>
    R3LocalPersistence(
        R3LocalStore(db, ownerId: owner, isCurrent: current ?? () => true),
        clock: () => DateTime.utc(2026, 11, 12));

Future<void> seed(AppDatabase db) async {
  final a = RabbitLocalStore(db).forOwner(1, () => true);
  await a.upsert(animal(child));
  await a.upsert(animal(father));
  await a.upsert(animal(mother, sex: 'female'));
  await a.upsert(animal(secondFather));
  await RabbitLocalStore(db)
      .forOwner(2, () => true)
      .upsert(animal(other, owner: 2));
}

void main() {
  group('account-scoped SQLite', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.memory();
      addTearDown(db.close);
      await seed(db);
    });

    test(
        'parent lifecycle preserves versions, role independence and ordered intents',
        () async {
      final r3 = service(db);
      final a = await r3.assignParent(
          childUuid: child, parentUuid: father, role: ParentRole.father);
      final m = await r3.assignParent(
          childUuid: child, parentUuid: mother, role: ParentRole.mother);
      final b = await r3.assignParent(
          childUuid: child,
          parentUuid: secondFather,
          role: ParentRole.father,
          version: a.version);
      final c = await r3.clearParent(
          childUuid: child, role: ParentRole.father, version: b.version);
      final d = await r3.assignParent(
          childUuid: child, parentUuid: father, role: ParentRole.father);
      expect([a.version, b.version, c.version, d.version], [1, 2, 3, 4]);
      expect(b.uuid, a.uuid);
      expect(c.uuid, a.uuid);
      expect(c.deletedAt, isNotNull);
      expect(d.uuid, isNot(a.uuid));
      expect(m.version, 1);
      expect((await r3.parentLinks()).where((row) => row.deletedAt == null),
          hasLength(2));
      final rows = await db.select(db.syncOperations).get();
      final fathers = [rows[0], rows[2], rows[3], rows[4]];
      expect(fathers.map((row) => row.operationType),
          ['CREATE', 'UPDATE', 'DELETE', 'CREATE']);
      expect(fathers.map((row) => row.baseVersion), [0, 1, 2, 0]);
      expect(jsonDecode(fathers[0].payload), isNot(contains('version')));
      for (var i = 1; i < fathers.length; i++) {
        expect(jsonDecode(fathers[i].dependencies),
            [fathers[i - 1].operationUuid]);
      }
      expect(
          await RabbitLocalStore(db)
              .forOwner(1, () => true)
              .readRetryableOperations(),
          isEmpty);
    });

    test(
        'genealogy rejects malformed IDs, wrong sex, cycles, stale versions and founders',
        () async {
      final r3 = service(db);
      Future<StoredParentLink> assign(String c, String p, {int? version}) =>
          r3.assignParent(
              childUuid: c,
              parentUuid: p,
              role: ParentRole.father,
              version: version);
      await expectLater(assign('invalid', father), throwsException);
      await expectLater(assign(child, mother), throwsException);
      await expectLater(assign(child, child), throwsException);
      await expectLater(assign(child, other), throwsException);
      await assign(child, father);
      await expectLater(
          assign(child, secondFather, version: 2), throwsException);
      await expectLater(assign(father, child), throwsException);
      await RabbitLocalStore(db)
          .forOwner(1, () => true)
          .upsert(animal(secondFather, knowledge: 'FOUNDER'));
      await expectLater(assign(secondFather, father), throwsException);
      expect(await r3.parentLinks(), hasLength(1));
      expect(await db.select(db.syncOperations).get(), hasLength(1));
    });

    test(
        'event keeps stable UUID and civil date; every edit and delete is recorded',
        () async {
      final r3 = service(db);
      await expectLater(
          r3.createEvent(
              maleUuid: father, femaleUuid: mother, matingDate: '2026-02-29'),
          throwsException);
      await expectLater(
          r3.createEvent(
              maleUuid: other, femaleUuid: mother, matingDate: '2024-02-29'),
          throwsException);
      final created = await r3.createEvent(
          maleUuid: father, femaleUuid: mother, matingDate: '2024-02-29');
      final edited =
          await r3.updateEvent(uuid: created.uuid, version: 1, notes: 'Edited');
      final again = await r3.updateEvent(
          uuid: created.uuid, version: 2, matingDate: '2024-12-31');
      final removed = await r3.deleteEvent(uuid: created.uuid, version: 3);
      expect([edited.version, again.version, removed.version], [2, 3, 4]);
      expect(removed.uuid, created.uuid);
      expect(removed.notes, 'Edited');
      expect(removed.matingDate, '2024-12-31');
      expect(removed.deletedAt, isNotNull);
      expect((await r3.event(created.uuid))!.deletedAt, removed.deletedAt);
      final rows = await db.select(db.syncOperations).get();
      expect(rows.map((row) => row.rabbitUuid).toSet(), {created.uuid});
      expect(rows.map((row) => row.operationType),
          ['CREATE', 'UPDATE', 'UPDATE', 'DELETE']);
      expect(jsonDecode(rows.last.entityReferences), [father, mother]);
      expect(jsonDecode(rows.last.dependencies), [rows[2].operationUuid]);

      final standalone = await r3.createEvent(
          maleUuid: father, femaleUuid: mother, matingDate: '2025-01-01');
      await r3.deleteEvent(uuid: standalone.uuid, version: 1);
      final finalRows = await db.select(db.syncOperations).get();
      expect(finalRows.skip(4).map((row) => row.operationType),
          ['CREATE', 'DELETE']);
    });

    test(
        'R3 waits for the same owner Rabbit CREATE and cannot depend on quarantine',
        () async {
      final a = RabbitLocalStore(db).forOwner(1, () => true);
      await a
          .upsert(animal(father, syncStatus: RabbitSyncStatus.pendingCreate));
      final r3 = service(db);
      await expectLater(
          r3.assignParent(
              childUuid: child, parentUuid: father, role: ParentRole.father),
          throwsStateError);
      expect(await r3.parentLinks(), isEmpty);
      await a.enqueueOrCoalesce(
          rabbitUuid: father,
          type: SyncOperationType.create,
          payload: '{}',
          baseVersion: 1);
      await r3.assignParent(
          childUuid: child, parentUuid: father, role: ParentRole.father);
      final rows = await db.select(db.syncOperations).get();
      expect(jsonDecode(rows.last.dependencies), [rows.first.operationUuid]);
      expect(jsonDecode(rows.last.entityReferences), [child, father]);
      expect(await a.readRetryableOperations(), hasLength(1));
    });

    test('other account cannot read, replace or delete R3 data', () async {
      final a = service(db);
      final b = service(db, owner: 2);
      final link = await a.assignParent(
          childUuid: child, parentUuid: father, role: ParentRole.father);
      final event = await a.createEvent(
          maleUuid: father, femaleUuid: mother, matingDate: '2026-01-01');
      expect(await b.parentLinks(), isEmpty);
      expect(await b.event(event.uuid), isNull);
      await expectLater(
          b.assignParent(
              childUuid: child,
              parentUuid: other,
              role: ParentRole.father,
              version: 1),
          throwsException);
      await expectLater(
          b.clearParent(childUuid: child, role: ParentRole.father, version: 1),
          throwsException);
      await expectLater(
          b.updateEvent(uuid: event.uuid, version: 1, notes: 'cross-account'),
          throwsException);
      await expectLater(
          b.deleteEvent(uuid: event.uuid, version: 1), throwsException);
      expect((await a.parentLinks()).single.uuid, link.uuid);
      expect((await a.event(event.uuid))!.version, 1);
      expect(
          (await db.select(db.syncOperations).get()).map((row) => row.ownerId),
          [1, 1]);
    });

    test(
        'outbox failure rolls back domain writes; domain and batch failures leave no intent',
        () async {
      final r3 = service(db);
      await db.customStatement("""
      CREATE TRIGGER fail_outbox BEFORE INSERT ON sync_operations
      BEGIN SELECT RAISE(ABORT,'outbox failed'); END
    """);
      await expectLater(
          r3.assignParent(
              childUuid: child, parentUuid: father, role: ParentRole.father),
          throwsException);
      await expectLater(
          r3.createEvent(
              maleUuid: father, femaleUuid: mother, matingDate: '2026-01-01'),
          throwsException);
      expect(await r3.parentLinks(), isEmpty);
      expect(await db.select(db.localReproductiveEvents).get(), isEmpty);
      await db.customStatement('DROP TRIGGER fail_outbox');
      await db.customStatement("""
      CREATE TRIGGER fail_event BEFORE INSERT ON local_reproductive_events
      BEGIN SELECT RAISE(ABORT,'event failed'); END
    """);
      await expectLater(db.transaction(() async {
        await r3.assignParent(
            childUuid: child, parentUuid: father, role: ParentRole.father);
        await r3.createEvent(
            maleUuid: father, femaleUuid: mother, matingDate: '2026-01-01');
      }), throwsException);
      expect(await r3.parentLinks(), isEmpty);
      expect(await db.select(db.syncOperations).get(), isEmpty);
    });

    test('invalid session at transaction end rolls back both entity and intent',
        () async {
      var checks = 0;
      final store = R3LocalStore(db, ownerId: 1, isCurrent: () => true);
      final r3 =
          R3LocalPersistence(store, canAccess: () async => ++checks == 1);
      await expectLater(
          r3.createEvent(
              maleUuid: father, femaleUuid: mother, matingDate: '2026-01-01'),
          throwsException);
      expect(await db.select(db.localReproductiveEvents).get(), isEmpty);
      expect(await db.select(db.syncOperations).get(), isEmpty);
    });

    test(
        'deferred constraint failure at commit rolls back an existing event edit',
        () async {
      final r3 = service(db);
      final event = await r3.createEvent(
          maleUuid: father, femaleUuid: mother, matingDate: '2026-01-01');
      await db.customStatement('PRAGMA foreign_keys = ON');
      await db
          .customStatement('CREATE TABLE test_parent (id INTEGER PRIMARY KEY)');
      await db.customStatement(
          'CREATE TABLE test_commit_guard (parent_id INTEGER REFERENCES test_parent(id) '
          'DEFERRABLE INITIALLY DEFERRED)');
      var reachedEnd = false;
      await expectLater(db.transaction(() async {
        await r3.updateEvent(
            uuid: event.uuid, version: event.version, notes: 'rolled back');
        await db.customStatement('INSERT INTO test_commit_guard VALUES (99)');
        reachedEnd = true;
      }), throwsException);
      expect(reachedEnd, isTrue);
      expect(await r3.event(event.uuid), event);
      expect(await db.select(db.syncOperations).get(), hasLength(1));
    });

    test('a removed cached parent can still be cleared without losing its UUID',
        () async {
      final r3 = service(db);
      final link = await r3.assignParent(
          childUuid: child, parentUuid: father, role: ParentRole.father);
      await RabbitLocalStore(db).forOwner(1, () => true).removeByUuid(father);
      final cleared = await r3.clearParent(
          childUuid: child, role: ParentRole.father, version: link.version);
      expect(cleared.uuid, link.uuid);
      expect(cleared.parentUuid, father);
      expect(cleared.deletedAt, isNotNull);
      final intent = (await db.select(db.syncOperations).get()).last;
      expect(jsonDecode(intent.entityReferences), [child, father]);
    });

    test('event notes respect the existing server limit', () async {
      final r3 = service(db);
      final oversized = List.filled(4001, 'a').join();
      await expectLater(
          r3.createEvent(
              maleUuid: father,
              femaleUuid: mother,
              matingDate: '2026-01-01',
              notes: oversized),
          throwsException);
      final event = await r3.createEvent(
          maleUuid: father,
          femaleUuid: mother,
          matingDate: '2026-01-01',
          notes: '  Observación  ');
      expect(event.notes, 'Observación');
      await expectLater(
          r3.updateEvent(uuid: event.uuid, version: 1, notes: oversized),
          throwsException);
      expect((await r3.event(event.uuid))!.version, 1);
      expect(await db.select(db.syncOperations).get(), hasLength(1));
    });

    test('R2 online drain skips R3 intents and leaves quarantine untouched',
        () async {
      final r3 = service(db);
      await r3.assignParent(
          childUuid: child, parentUuid: father, role: ParentRole.father);
      await r3.createEvent(
          maleUuid: father, femaleUuid: mother, matingDate: '2026-01-01');
      await db.into(db.syncOperations).insert(SyncOperationsCompanion.insert(
            rabbitUuid: father,
            operationType: 'CREATE',
            payload: '{}',
            baseVersion: 1,
            createdAt: 'legacy',
            quarantineReason: const Value('legacy:unproven_owner'),
          ));
      final previous = await db.select(db.syncOperations).get();
      final api = ApiClient(
          baseUrl: 'https://test.invalid',
          httpClient:
              MockClient((_) async => fail('Unexpected HTTP publication')));
      final connection = FakeConnectivity(online: true);
      addTearDown(connection.close);
      await SyncEngine(
              api, RabbitLocalStore(db).forOwner(1, () => true), connection)
          .syncPending();
      expect(await db.select(db.syncOperations).get(), previous);
    });

    test('SQLite prevents a second active role and an invalid owner', () async {
      final link = await service(db).assignParent(
          childUuid: child, parentUuid: father, role: ParentRole.father);
      await expectLater(
          db.into(db.localParentLinks).insert(link.copyWith(uuid: 'duplicate')),
          throwsException);
      await expectLater(
          db
              .into(db.localParentLinks)
              .insert(link.copyWith(uuid: 'bad-owner', ownerId: 0)),
          throwsException);
    });
  });

  test('closing and reopening keeps both R3 UUIDs and their intents', () async {
    final dir = await Directory.systemTemp.createTemp('cunismart_r3_durable_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/test.sqlite');
    final first = AppDatabase.file(file);
    await seed(first);
    final before = service(first);
    final link = await before.assignParent(
        childUuid: child, parentUuid: father, role: ParentRole.father);
    final event = await before.createEvent(
        maleUuid: father, femaleUuid: mother, matingDate: '2026-01-01');
    await first.close();

    final reopened = AppDatabase.file(file);
    addTearDown(reopened.close);
    final after = service(reopened);
    expect((await after.parentLinks()).single, link);
    expect(await after.event(event.uuid), event);
    expect(
        (await reopened.select(reopened.syncOperations).get())
            .map((row) => row.rabbitUuid),
        [link.uuid, event.uuid]);
  });
}
