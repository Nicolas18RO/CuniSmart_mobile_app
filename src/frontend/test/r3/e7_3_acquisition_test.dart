import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/data/local/r3_acquisition.dart';
import 'package:frontend/data/local/sync_evidence_store.dart';

void main() {
  test('acquisition waits for Rabbit and remote version, then uses mapped UUID',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final store =
        SyncEvidenceStore(db, ownerId: 1, generation: 1, isCurrent: () => true);
    final acquisition = R3Acquisition(store);
    await db.customStatement("""
      INSERT INTO rabbits (uuid,user_id,name,breed,sex,birth_date,status,created_at,updated_at)
      VALUES ('m',1,'Male','rex','male','2024-01-01','active','then','then'),
             ('f',1,'Female','rex','female','2024-01-01','active','then','then')
    """);
    await db.customStatement("""
      INSERT INTO sync_operations
        (owner_id,operation_uuid,entity_type,rabbit_uuid,operation_type,payload,
         base_version,created_at,dependencies,entity_references)
      VALUES (1,'rabbit','RABBIT','m','CREATE','{}',0,'then','[]','[]'),
             (1,'create','REPRODUCTIVE_EVENT','local','CREATE',
              '{"male_uuid":"m","female_uuid":"f","mating_date":"2026-11-13"}',
              0,'then','["rabbit"]','["m","f"]'),
             (1,'edit','REPRODUCTIVE_EVENT','local','UPDATE',
              '{"male_uuid":"m","female_uuid":"f","notes":"later"}',
              21,'then','["create"]','["m","f"]'),
             (1,'unknown','REPRODUCTIVE_EVENT','unknown','DELETE','{}',8,'then','[]','[]')
    """);
    expect(await acquisition.next({}), isNull);
    expect((await store.operation('unknown'))?.lastError,
        'r3_remote_evidence_missing');
    await db.customStatement('UPDATE rabbits SET server_id = 10');
    await db.customStatement(
        "UPDATE sync_operations SET status='COMPLETED' WHERE operation_uuid='rabbit'");
    final create = (await acquisition.next({}))!;
    expect(create.operationUuid, 'create');
    expect(await acquisition.next({}), isNull);
    expect(
        await store.apply(create,
            remoteReceipt: '1',
            statusCode: 201,
            confirmedAt: 'then',
            remoteEntityUuid: 'remote',
            remoteVersion: 3),
        isTrue);
    final edit = (await acquisition.next({}))!;
    expect(edit.operationUuid, 'edit');
    expect(edit.command, contains('/api/reproductive-events/remote/'));
    expect(edit.command, contains('"expectedVersion":3'));
    expect(edit.command, isNot(contains('male_uuid')));
  });
}
