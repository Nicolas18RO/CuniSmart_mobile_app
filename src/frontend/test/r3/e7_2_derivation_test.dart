import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/data/local/sync_command.dart';
import 'package:frontend/data/local/sync_dependency_evaluator.dart';
import 'package:frontend/data/local/sync_evidence_store.dart';

void main() {
  test(
      'derivation survives reopen, preserves origin and gates only explicit causality',
      () async {
    final dir = await Directory.systemTemp.createTemp('cunismart_derivation_');
    final file = File('${dir.path}/db.sqlite');
    var db = AppDatabase.file(file);
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });
    var current = true;
    SyncEvidenceStore scope(int owner) => SyncEvidenceStore(db,
        ownerId: owner, generation: 1, isCurrent: () => current);
    var store = scope(1);
    const destination = '/reproductive-events/123/';
    final original = canonicalSyncCommand(
      entityType: 'REPRODUCTIVE_EVENT',
      action: 'DELETE',
      destination: destination,
      payload: {},
      expectedVersion: 1,
    );
    await db.customStatement("""
      INSERT INTO sync_operations
        (owner_id,operation_uuid,entity_type,rabbit_uuid,operation_type,payload,base_version,created_at)
      VALUES (1,'original','REPRODUCTIVE_EVENT','local','DELETE','{}',1,'then')
    """);
    await store.freeze('original', original, syncRequestHash(original));
    final attempt = (await store.claim('original'))!;
    Future<String> derive({bool causal = false}) => store.derive('original',
        destination: destination,
        payload: {},
        expectedVersion: 2,
        requiresOriginalResult: causal);

    await expectLater(
        scope(2).derive('original',
            destination: destination, payload: {}, expectedVersion: 2),
        throwsStateError);
    await expectLater(
        store.derive('missing', destination: destination, payload: {}),
        throwsStateError);
    await expectLater(
        store.derive('original',
            destination: destination, payload: {}, expectedVersion: 1),
        throwsArgumentError);
    current = false;
    await expectLater(derive(), throwsStateError);
    current = true;

    for (final table in ['sync_operations', 'sync_frozen_commands']) {
      await db.customStatement("""
        CREATE TRIGGER reject_derivation BEFORE INSERT ON $table
        BEGIN SELECT RAISE(ABORT, 'injected'); END
      """);
      await expectLater(derive(), throwsException);
      await db.customStatement('DROP TRIGGER reject_derivation');
    }
    await expectLater(db.transaction(() async {
      await derive();
      throw StateError('before commit');
    }), throwsStateError);
    expect(await db.select(db.syncOperations).get(), hasLength(1));

    final traced = await derive();
    final causal = await derive(causal: true);
    expect({traced, causal, 'original'}, hasLength(3));
    await db.close();
    db = AppDatabase.file(file);
    store = scope(1);
    expect(await store.originOf(traced), 'original');
    expect(await store.originOf(causal), 'original');
    expect(await store.originOf('original'), isNull);
    final dag = await SyncDependencyEvaluator(store).evaluate();
    expect(dag.eligible, [traced]);
    expect(dag.blocked[causal], SyncBlock.waiting);
    expect((await store.operation(traced))?.status, 'PENDING');
    final child = (await store.claim(traced))!;
    expect(child.attemptUuid, isNot(attempt.attemptUuid));
    expect(child.requestHash, isNot(attempt.requestHash));
    final originalRow = (await db
        .customSelect(
          "SELECT * FROM sync_frozen_commands WHERE operation_uuid = 'original'",
        )
        .getSingle());
    expect(originalRow.read<String>('canonical_command'), original);
    expect(originalRow.read<String>('attempt_uuid'), attempt.attemptUuid);
  });

  test('derivation can change action without mutating the frozen origin', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    var current = true;
    final store = SyncEvidenceStore(db,
        ownerId: 1, generation: 1, isCurrent: () => current);
    const destination = '/api/reproductive-events/123/';
    final original = canonicalSyncCommand(
      entityType: 'REPRODUCTIVE_EVENT',
      action: 'CREATE',
      destination: '/api/reproductive-events/',
      payload: {'male_uuid': 'm', 'female_uuid': 'f', 'mating_date': '2026-01-01'},
    );
    await db.customStatement("""
      INSERT INTO sync_operations
        (owner_id,operation_uuid,entity_type,rabbit_uuid,operation_type,payload,base_version,created_at)
      VALUES (1,'origin-create','REPRODUCTIVE_EVENT','local','CREATE',?,1,'now')
    """, [jsonEncode({'male_uuid': 'm', 'female_uuid': 'f', 'mating_date': '2026-01-01'})]);
    await store.freeze('origin-create', original, syncRequestHash(original));
    await db.customStatement('''
      INSERT INTO sync_identity_mappings
        (owner_id,entity_type,local_uuid,remote_entity_uuid,child_uuid,role,creation_version)
      VALUES (1,'REPRODUCTIVE_EVENT','local','99999999-9999-4999-8999-999999999999',NULL,NULL,NULL)
    ''');
    final derived = await store.derive('origin-create',
        action: 'UPDATE',
        destination: destination,
        payload: {'notes': 'corrected'},
        expectedVersion: 1,
        requiresOriginalResult: true);
    expect((await store.operation('origin-create'))?.operationType, 'CREATE');
    expect((await store.operation(derived))?.operationType, 'UPDATE');
    expect(await store.originOf(derived), 'origin-create');
    final frozen = await db.customSelect(
        "SELECT canonical_command FROM sync_frozen_commands WHERE operation_uuid='origin-create'").getSingle();
    expect(frozen.read<String>('canonical_command'), original);
    expect(syncRequestHash(original), isNot(syncRequestHash(
        (await db.customSelect('SELECT canonical_command FROM sync_frozen_commands WHERE operation_uuid=?', variables: [Variable(derived)]).getSingle()).read<String>('canonical_command'))));
  });
}
