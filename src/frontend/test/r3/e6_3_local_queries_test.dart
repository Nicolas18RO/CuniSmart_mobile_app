import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/domain/genealogy/parent_link.dart';
import 'package:frontend/features/r3/application/r3_local_persistence.dart';
import 'package:frontend/features/r3/data/r3_local_store.dart';
import 'package:frontend/features/r3/data/local_r3_queries.dart';
import 'package:frontend/features/r3/domain/r3_local_results.dart';
import 'package:frontend/models/sync_status.dart';
import 'package:frontend/models/sync_operation.dart';
import 'package:frontend/services/rabbit_local_store.dart';

import 'e6_2_local_persistence_test.dart'
    show seed, animal, child, father, mother;

void main() {
  late AppDatabase db;
  late LocalR3Queries queries;
  late R3LocalPersistence writes;
  late RabbitLocalStore rabbits;
  late bool current;

  setUp(() async {
    db = AppDatabase.memory();
    addTearDown(db.close);
    await seed(db);
    current = true;
    final store = R3LocalStore(db, ownerId: 1, isCurrent: () => current);
    queries = LocalR3Queries(store);
    writes = R3LocalPersistence(store);
    rabbits = RabbitLocalStore(db).forOwner(1, () => true);
  });

  test(
      'roles, inverse lookup, history and account scope preserve edge identity',
      () async {
    final edge = await writes.assignParent(
        childUuid: child, parentUuid: father, role: ParentRole.father);
    expect((await queries.parents(child, role: ParentRole.father)).single.uuid,
        edge.uuid);
    expect(await queries.parents(child, role: ParentRole.mother), isEmpty);
    expect((await queries.children(father)).single.link.childUuid, child);
    final foreign =
        LocalR3Queries(R3LocalStore(db, ownerId: 2, isCurrent: () => true));
    expect(await foreign.children(father), isEmpty);
    await writes.clearParent(
        childUuid: child, role: ParentRole.father, version: edge.version);
    expect(await queries.parents(child), isEmpty);
    final history = (await queries.parents(child, includeDeleted: true)).single;
    expect(history.uuid, edge.uuid);
    expect(history.link.version, 2);
    expect(history.link.isActive, isFalse);
    expect((await queries.genealogy([child])).deletedLinks, isEmpty);
    expect(
        (await queries.genealogy([child], includeDeleted: true))
            .deletedLinks
            .single
            .uuid,
        edge.uuid);
    current = false;
    await expectLater(queries.parents(child), throwsException);
  });

  test('civil dates, calendar window, missing participant and historical event',
      () async {
    final one = await writes.createEvent(
        maleUuid: father, femaleUuid: mother, matingDate: '2024-01-29');
    final two = await writes.createEvent(
        maleUuid: father, femaleUuid: mother, matingDate: '2024-12-01');
    await writes.updateEvent(uuid: one.uuid, version: 1, notes: 'updated');
    final range = await queries.events(
        participantUuid: mother,
        role: ReproductiveRole.female,
        from: '2024-01-29',
        to: '2024-12-01');
    expect(range.map((e) => e.uuid), [one.uuid, two.uuid]);
    expect(range.first.male.uuid, father);
    expect(range.first.female.uuid, mother);
    expect(range.first.notes, 'updated');
    expect(range.first.estimatedBirthDate, '2024-02-29');
    expect(
        await queries.events(
            participantUuid: mother, role: ReproductiveRole.male),
        isEmpty);
    expect(
        (await queries.calendar('2024-02-29', '2024-02-29',
                today: '2024-02-29'))
            .single
            .calendarState,
        'DUE_TODAY');
    await rabbits.removeByUuid(mother);
    expect(
        (await queries.events(participantUuid: mother))
            .first
            .female
            .availability,
        LocalRabbitAvailability.unavailable);
    final foreign =
        LocalR3Queries(R3LocalStore(db, ownerId: 2, isCurrent: () => true));
    expect(await foreign.events(), isEmpty);
    await writes.deleteEvent(uuid: one.uuid, version: 2);
    expect((await queries.events()).map((e) => e.uuid), [two.uuid]);
    expect((await queries.events(includeDeleted: true)).first.deletedAt,
        isNotNull);
    current = false;
    await expectLater(queries.events(), throwsException);
  });

  test('Wright uses evidence for partial and exact, never assumes a founder',
      () async {
    final noEvidence = await queries.genealogy([child, father]);
    expect(noEvidence.evaluation!.status, 'NO_CALCULABLE');
    expect(noEvidence.evaluation!.relationship, isNull);
    expect(noEvidence.unknownParents[child], containsAll(ParentRole.values));
    await writes.assignParent(
        childUuid: child, parentUuid: father, role: ParentRole.father);
    final partial = await queries.genealogy([child, father]);
    expect(partial.evaluation!.status, 'PARTIAL');
    expect(partial.evaluation!.expectedInbreeding, isNull);
    expect(partial.unknownParents[child], [ParentRole.mother]);
    await writes.assignParent(
        childUuid: child, parentUuid: mother, role: ParentRole.mother);
    await rabbits.upsert(animal(father, knowledge: 'FOUNDER'));
    await rabbits.upsert(animal(mother, sex: 'female', knowledge: 'FOUNDER'));
    final exact = await queries.genealogy([child, father]);
    expect(exact.evaluation!.status, 'CALCULABLE');
    expect(exact.evaluation!.relationship!.toDecimalString(), '0.5');
    expect(exact.depthExplored, 1);
    expect(exact.confirmedFounders, containsAll([father, mother]));
    final truncated = await queries.genealogy([child, father], maxDepth: 0);
    expect(truncated.evaluation!.status, isNot('CALCULABLE'));
    expect(truncated.depthLimited, isTrue);
    await rabbits.removeByUuid(father);
    final missing = await queries.genealogy([child, father]);
    expect(missing.unavailable, contains(father));
    expect(missing.evaluation!.status, 'NO_CALCULABLE');
    expect(missing.evaluation!.relationship, isNull);
  });

  test(
      'pending participant stays distinct and cancelled R2 dependency remains intact',
      () async {
    await rabbits
        .upsert(animal(father, syncStatus: RabbitSyncStatus.pendingCreate));
    await db.customStatement(
      "INSERT INTO sync_operations(owner_id,operation_uuid,rabbit_uuid,operation_type,payload,base_version,created_at) VALUES (1,'dep',?,'CREATE','{}',1,'now')",
      [father],
    );
    final event = await writes.createEvent(
        maleUuid: father, femaleUuid: mother, matingDate: '2026-01-01');
    expect((await queries.events()).single.male.availability,
        LocalRabbitAvailability.pendingCreate);
    await rabbits.transaction(() => rabbits.enqueueOrCoalesce(
          rabbitUuid: father,
          type: SyncOperationType.delete,
          payload: '{}',
          baseVersion: 1,
        ));
    expect(await rabbits.readByUuid(father), isNull);
    expect((await queries.events()).single.uuid, event.uuid);
    expect((await queries.events()).single.male.availability,
        LocalRabbitAvailability.unavailable);
    final intent = (await db.select(db.syncOperations).get()).single;
    expect(intent.dependencies, '["dep"]');
  });

  test('cycles terminate and suppress numeric results', () async {
    await writes.assignParent(
        childUuid: child, parentUuid: father, role: ParentRole.father);
    await db.customStatement(
      "INSERT INTO local_parent_links(uuid,owner_id,child_uuid,parent_uuid,role,version,created_at,updated_at) VALUES ('corrupt',1,?,?,'FATHER',1,'now','now')",
      [father, child],
    );
    final graph = await queries.genealogy([child, father]);
    expect(graph.hasCycle, isTrue);
    expect(graph.evaluation!.status, 'NO_CALCULABLE');
    expect(graph.evaluation!.relationship, isNull);
  });

  test('descendants are bounded and quarantine masks rabbit facts', () async {
    await writes.assignParent(
        childUuid: child, parentUuid: father, role: ParentRole.father);
    await writes.assignParent(
        childUuid: father, parentUuid: mother, role: ParentRole.mother);
    final graph = await queries.genealogy([child]);
    expect(graph.nodes.keys, containsAll([child, father, mother]));
    expect(graph.depthExplored, 2);
    expect((await queries.parents(child)).single.link.syncStatus,
        RabbitSyncStatus.pendingCreate);
    final descendants = await queries.genealogy([mother], descendants: true);
    expect(descendants.nodes, hasLength(3));
    expect(descendants.links, hasLength(2));
    expect(descendants.coverage, GenealogyCoverage.incomplete);
    await db.customStatement(
        "UPDATE rabbits SET quarantine_reason = 'legacy:unknown_owner' WHERE uuid = ?",
        [father]);
    final unavailable = await queries.genealogy([child]);
    expect(unavailable.nodes[father]!.rabbit, isNull);
    expect(unavailable.links.first.parent.uuid, father);
    expect(unavailable.coverage, GenealogyCoverage.incomplete);
  });

  test('authorization lost during the query suppresses the result', () async {
    var checks = 0;
    final guarded = LocalR3Queries(
      R3LocalStore(db, ownerId: 1, isCurrent: () => true),
      canAccess: () async => ++checks == 1,
    );
    await expectLater(guarded.genealogy([child]), throwsException);
  });
}
