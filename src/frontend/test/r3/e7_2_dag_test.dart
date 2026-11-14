import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/data/local/sync_command.dart';
import 'package:frontend/data/local/sync_dependency_evaluator.dart';
import 'package:frontend/data/local/sync_evidence_store.dart';

void main() {
  test('Rabbit completion releases a link and a two-participant event',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final scope =
        SyncEvidenceStore(db, ownerId: 1, generation: 1, isCurrent: () => true);
    await db.customStatement("""
      INSERT INTO rabbits
        (uuid,user_id,name,breed,sex,birth_date,status,created_at,updated_at)
      VALUES ('m',1,'Male','rex','male','2024-01-01','active','then','then'),
             ('f',1,'Female','rex','female','2024-01-01','active','then','then')
    """);
    await db.customStatement("""
      INSERT INTO sync_operations
        (owner_id,operation_uuid,entity_type,rabbit_uuid,operation_type,payload,
         base_version,created_at,dependencies,entity_references)
      VALUES (1,'m-create','RABBIT','m','CREATE','{}',0,'then','[]','[]'),
             (1,'f-create','RABBIT','f','CREATE','{}',0,'then','[]','[]'),
             (1,'link','PARENT_LINK','link','CREATE',
              '{"child_uuid":"f","parent_uuid":"m","role":"FATHER"}',
              0,'then','["m-create","f-create"]','["f","m"]'),
             (1,'event','REPRODUCTIVE_EVENT','event','CREATE',
              '{"male_uuid":"m","female_uuid":"f"}',
              0,'then','["m-create","f-create"]','["m","f"]')
    """);
    final evaluator = SyncDependencyEvaluator(scope);
    expect((await evaluator.evaluate()).eligible, isEmpty);
    await db
        .customStatement("UPDATE rabbits SET server_id = 10 WHERE uuid = 'm'");
    await db.customStatement(
        "UPDATE sync_operations SET status = 'COMPLETED' WHERE operation_uuid = 'm-create'");
    expect((await evaluator.evaluate()).eligible, isEmpty);
    await db
        .customStatement("UPDATE rabbits SET server_id = 11 WHERE uuid = 'f'");
    await db.customStatement(
        "UPDATE sync_operations SET status = 'COMPLETED' WHERE operation_uuid = 'f-create'");
    expect((await evaluator.evaluate()).eligible, ['link', 'event']);

    await db.customStatement("""
      INSERT INTO sync_operations
        (owner_id,operation_uuid,entity_type,rabbit_uuid,operation_type,payload,
         base_version,created_at)
      VALUES (1,'m-update','RABBIT','m','UPDATE','{}',1,'then')
    """);
    await db.customStatement(
        "UPDATE rabbits SET sync_status = 'PENDING_UPDATE' WHERE uuid = 'm'");
    expect((await evaluator.evaluate()).eligible, isEmpty);
    await db.customStatement(
        "INSERT INTO sync_rabbit_preimages VALUES (1,'m-update','male','active','UNKNOWN')");
    expect((await evaluator.evaluate()).eligible, ['link', 'event']);
    await db.customStatement(
        "UPDATE sync_rabbit_preimages SET status = 'inactive' WHERE operation_uuid = 'm-update'");
    expect((await evaluator.evaluate()).eligible, ['link']);
  });

  test('DAG propagates cycle, conflict, cancellation and absent evidence',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final scope =
        SyncEvidenceStore(db, ownerId: 1, generation: 1, isCurrent: () => true);
    Future<void> add(String id, String deps,
            {String status = 'PENDING', String? quarantine, int owner = 1}) =>
        db.customStatement("""
          INSERT INTO sync_operations
            (owner_id, operation_uuid, entity_type, rabbit_uuid, operation_type,
             payload, base_version, created_at, dependencies, status, quarantine_reason)
          VALUES (?, ?, 'REPRODUCTIVE_EVENT', ?, 'DELETE', '{}', 1, 'then', ?, ?, ?)
        """, [owner, id, id, deps, status, quarantine]);
    await add('a', '["b"]');
    await add('b', '["a"]');
    await add('cycle-child', '["a"]');
    await add('conflict', '[]', status: 'CONFLICT');
    await add('conflict-child', '["conflict"]');
    await add('legacy', '[]', quarantine: 'legacy');
    await add('legacy-child', '["legacy"]');
    await add('foreign', '[]', owner: 2);
    await add('orphan', '["foreign"]');
    await add('cancel-child', '["cancel"]');
    await add('independent', '[]');
    await db.customStatement("""
      INSERT INTO sync_create_cancellations VALUES (1, 'cancel', 'r', 'cancelled', 'then')
    """);
    final plan = await SyncDependencyEvaluator(scope).evaluate();
    expect(plan.eligible, ['independent']);
    expect(plan.blocked, {
      'a': SyncBlock.cycle,
      'b': SyncBlock.cycle,
      'cycle-child': SyncBlock.cycle,
      'conflict': SyncBlock.conflict,
      'conflict-child': SyncBlock.conflict,
      'legacy': SyncBlock.quarantine,
      'legacy-child': SyncBlock.quarantine,
      'orphan': SyncBlock.missing,
      'cancel-child': SyncBlock.cancelled,
    });
    expect((await scope.operation('cancel-child'))?.status, 'PENDING');
  });

  test('recovers abandoned attempt with same bytes and discards stale result',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.customStatement("""
      INSERT INTO sync_operations
        (owner_id, operation_uuid, entity_type, rabbit_uuid, operation_type,
         payload, base_version, created_at)
      VALUES (1, 'event', 'REPRODUCTIVE_EVENT', 'event', 'CREATE', '{}', 0, 'then')
    """);
    var generation = 1;
    final old = SyncEvidenceStore(db,
        ownerId: 1, generation: 1, isCurrent: () => generation == 1);
    await old.freeze('event', '{}', syncRequestHash('{}'));
    final abandoned = (await old.claim('event'))!;
    generation = 2;
    final offline = SyncEvidenceStore(db,
        ownerId: 1, generation: 2, isCurrent: () => false);
    await expectLater(
        offline.claim('event', recovering: true), throwsStateError);
    final current = SyncEvidenceStore(db,
        ownerId: 1, generation: 2, isCurrent: () => generation == 2);
    final recovered = (await current.claim('event', recovering: true))!;
    expect(recovered.attemptUuid, isNot(abandoned.attemptUuid));
    expect(recovered.operationUuid, abandoned.operationUuid);
    expect(recovered.command, abandoned.command);
    expect(recovered.requestHash, abandoned.requestHash);
    expect(await current.claim('event', recovering: true), isNull);
    expect(
        await old.apply(abandoned,
            remoteReceipt: 'r',
            statusCode: 201,
            confirmedAt: 'then',
            remoteEntityUuid: 'remote'),
        isFalse);
    expect(
        await current.apply(recovered,
            remoteReceipt: 'r',
            statusCode: 201,
            confirmedAt: 'then',
            remoteEntityUuid: 'remote'),
        isTrue);
    await db.customStatement(
        "UPDATE sync_operations SET status = 'SYNCING' WHERE operation_uuid = 'event'");
    expect(await current.claim('event', recovering: true), isNull);
    expect((await current.operation('event'))?.status, 'COMPLETED');
  });
}
