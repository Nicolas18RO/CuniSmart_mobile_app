import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/data/local/sync_command.dart';
import 'package:frontend/data/local/sync_evidence_store.dart';
import 'package:frontend/models/local_uuid.dart';

void main() {
  test('live PostgreSQL receipts survive lost responses and Drift rollback',
      () async {
    final runUuid = newLocalUuid();
    Future<Map<String, Object?>> probe(Map<String, Object?> request) async {
      final process = await Process.start(
        File('../backend/venv/Scripts/python.exe').absolute.path,
        ['-m', 'core.e72_replay_probe'],
        workingDirectory: '../backend',
      );
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      process.stdin
          .add(utf8.encode(jsonEncode({...request, 'runUuid': runUuid})));
      await process.stdin.close();
      expect(await process.exitCode, 0, reason: await stderr);
      return (jsonDecode(await stdout) as Map).cast<String, Object?>();
    }

    final setup = await probe({'setup': true});
    final owner = setup['ownerId'] as int;
    final dir = await Directory.systemTemp.createTemp('cunismart_live_replay_');
    final file = File('${dir.path}/drift.sqlite');
    var db = AppDatabase.file(file);
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });
    var generation = 1;
    SyncEvidenceStore scoped(int account) {
      final captured = generation;
      return SyncEvidenceStore(db,
          ownerId: account,
          generation: captured,
          isCurrent: () => captured == generation);
    }

    var store = scoped(owner);
    Future<FrozenAttempt> create({bool parent = false}) async {
      final uuid = newLocalUuid();
      final entity = parent ? 'PARENT_LINK' : 'REPRODUCTIVE_EVENT';
      final payload = parent
          ? {
              'child_uuid': setup['female'],
              'parent_uuid': setup['male'],
              'role': 'FATHER'
            }
          : {
              'male_uuid': setup['male'],
              'female_uuid': setup['female'],
              'mating_date': '2025-05-01',
              'notes': 'Cría 🐇'
            };
      final command = canonicalSyncCommand(
        entityType: entity,
        action: 'CREATE',
        destination: parent
            ? '/rabbits/${setup['female']}/parents/FATHER/'
            : '/reproductive-events/',
        payload: payload,
      );
      await db.customStatement("""
        INSERT INTO sync_operations
          (owner_id,operation_uuid,entity_type,rabbit_uuid,operation_type,payload,base_version,created_at)
        VALUES (?, ?, ?, ?, 'CREATE', ?, 0, 'then')
      """, [owner, uuid, entity, 'local-$uuid', jsonEncode(payload)]);
      await store.freeze(uuid, command, syncRequestHash(command));
      return (await store.claim(uuid))!;
    }

    Future<Map<String, Object?>> send(FrozenAttempt attempt,
            {String? command}) =>
        probe({
          'operationUuid': attempt.operationUuid,
          'command': command ?? attempt.command
        });

    final first = await create();
    final original = await send(first);
    expect(original['events'], 1);
    expect(original['receipts'], 1);
    expect(await store.applyReceipt(first, original), isTrue);

    final abandoned = await create();
    final lost = await send(abandoned);
    expect(lost['events'], 2);
    generation++;
    store = scoped(owner);
    final retry =
        (await store.claim(abandoned.operationUuid, recovering: true))!;
    expect(retry.attemptUuid, isNot(abandoned.attemptUuid));
    expect(retry.command, abandoned.command);
    expect(retry.requestHash, abandoned.requestHash);
    final replay = await send(retry);
    expect(replay, lost);
    expect(await store.applyReceipt(abandoned, replay), isFalse);
    expect(await scoped(owner + 1).applyReceipt(retry, replay), isFalse);
    expect(
        await store.applyReceipt(retry, {...replay, 'requestHash': 'invalid'}),
        isFalse);

    await db.customStatement("""
      CREATE TRIGGER reject_result BEFORE INSERT ON sync_operation_results
      BEGIN SELECT RAISE(ABORT, 'injected'); END
    """);
    await expectLater(store.applyReceipt(retry, replay), throwsException);
    expect((await store.operation(retry.operationUuid))?.status, 'SYNCING');
    expect(await db.customSelect('SELECT * FROM sync_identity_mappings').get(),
        hasLength(1));
    await db.close();
    db = AppDatabase.file(file);
    await db.customStatement('DROP TRIGGER reject_result');
    generation++;
    store = scoped(owner);
    final recovered =
        (await store.claim(retry.operationUuid, recovering: true))!;
    expect(await send(recovered), lost);
    expect(await store.applyReceipt(recovered, lost), isTrue);
    final changed = await send(recovered,
        command: recovered.command.replaceFirst('Cría', 'Otra'));
    expect(changed, {'conflict': true, 'events': 2});
    expect(
        (await store.operation(recovered.operationUuid))?.status, 'COMPLETED');

    final parent = await create(parent: true);
    final link = await send(parent);
    expect(link['links'], 1);
    expect(link['receipts'], 3);
    expect(
      await store.applyReceipt(parent, {
        ...link,
        'remoteIdentity': {'childUuid': setup['male'], 'role': 'FATHER'},
      }),
      isFalse,
    );
    expect(await store.applyReceipt(parent, link), isTrue);
    await db.close();
    db = AppDatabase.file(file);
    final mappings = await db
        .customSelect(
          'SELECT * FROM sync_identity_mappings ORDER BY entity_type',
        )
        .get();
    expect(mappings, hasLength(3));
    expect(mappings.first.readNullable<String>('remote_entity_uuid'), isNull);
    expect(mappings.first.read<String>('child_uuid'), setup['female']);
    expect(mappings.first.read<String>('role'), 'FATHER');
    expect(mappings.first.read<int>('creation_version'), link['remoteVersion']);
    final event = mappings.singleWhere((row) =>
        row.read<String>('local_uuid') == 'local-${retry.operationUuid}');
    expect(event.read<String>('remote_entity_uuid'),
        (lost['remoteIdentity'] as Map)['uuid']);
  }, skip: Platform.environment['E72_LIVE_REPLAY'] != '1');
}
