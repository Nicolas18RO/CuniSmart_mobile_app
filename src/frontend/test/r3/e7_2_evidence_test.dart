import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/data/local/sync_command.dart';
import 'package:frontend/data/local/sync_evidence_store.dart';

void main() {
  test('frozen command is immutable and scoped; result and mapping are atomic',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.customStatement("""
      INSERT INTO sync_operations
        (owner_id, operation_uuid, entity_type, rabbit_uuid, operation_type,
         payload, base_version, created_at)
      VALUES (1, 'op', 'REPRODUCTIVE_EVENT', 'local', 'CREATE', '{}', 0, 'then')
    """);
    var current = true;
    final store = SyncEvidenceStore(db,
        ownerId: 1, generation: 1, isCurrent: () => current);
    final other =
        SyncEvidenceStore(db, ownerId: 2, generation: 1, isCurrent: () => true);
    final hash = syncRequestHash('{}');
    await store.freeze('op', '{}', hash);
    await store.freeze('op', '{}', hash);
    const edited = '{"edit":true}';
    await expectLater(store.freeze('op', edited, hash), throwsArgumentError);
    await expectLater(
        store.freeze('op', edited, syncRequestHash(edited)), throwsStateError);
    await expectLater(other.freeze('op', '{}', hash), throwsStateError);
    final attempts = await Future.wait([store.claim('op'), store.claim('op')]);
    final attempt = attempts.whereType<FrozenAttempt>().single;
    expect(attempt.command, '{}');
    expect(attempt.requestHash, hash);

    Future<bool> apply(SyncEvidenceStore scope, int status) =>
        scope.apply(attempt,
            remoteReceipt: 'receipt',
            statusCode: status,
            confirmedAt: 'then',
            remoteEntityUuid: 'remote',
            remoteVersion: 1);
    expect(await apply(other, 201), isFalse);
    await expectLater(apply(store, 500), throwsException);
    expect(await db.customSelect('SELECT * FROM sync_identity_mappings').get(),
        isEmpty);
    expect((await store.operation('op'))?.status, 'SYNCING');
    current = false;
    expect(await apply(store, 201), isFalse);
    current = true;
    expect(await apply(store, 201), isTrue);
    expect(await apply(store, 201), isFalse);
    expect((await store.operation('op'))?.status, 'COMPLETED');
  });
}
