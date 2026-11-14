import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/data/local/sync_evidence_store.dart';
import 'package:frontend/models/local_uuid.dart';
import 'package:frontend/services/r3_publisher.dart';
import 'package:http/http.dart' as http;

class FaultClient extends http.BaseClient {
  final inner = http.Client();
  bool drop = false;
  bool strip = false;
  Future<void> Function()? afterCommit;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    final body = await response.stream.toBytes();
    await afterCommit?.call();
    afterCommit = null;
    if (drop) {
      drop = false;
      throw http.ClientException('Injected response loss');
    }
    final headers = {...response.headers};
    if (strip) {
      strip = false;
      headers.remove('x-cunismart-sync-receipt');
    }
    return http.StreamedResponse(Stream.value(body), response.statusCode,
        headers: headers);
  }

  @override
  void close() => inner.close();
}

void main() {
  test('all six R3 writes replay through Django HTTP and PostgreSQL', () async {
    final config = jsonDecode(
            File(Platform.environment['E73_HTTP_FIXTURE']!).readAsStringSync())
        as Map<String, dynamic>;
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final fault = FaultClient();
    addTearDown(fault.close);
    final client =
        ApiClient(httpClient: fault, baseUrl: config['baseUrl'] as String)
          ..accessToken = config['token'] as String;
    final owner = config['owner'] as int;
    final male = config['male'] as String;
    final female = config['female'] as String;
    const generation = 1;
    var current = true;
    final store = SyncEvidenceStore(db,
        ownerId: owner, generation: generation, isCurrent: () => current);
    final publisher = R3Publisher(client, store);

    for (final pair in [(male, 'male'), (female, 'female')]) {
      await db.customStatement("""
        INSERT INTO rabbits (uuid,user_id,server_id,name,breed,sex,birth_date,status,created_at,updated_at)
        VALUES (?, ?, 1, 'Rabbit', 'rex', ?, '2024-01-01','active','then','then')
      """, [pair.$1, owner, pair.$2]);
    }
    Future<void> drain() => publisher.drain(() async => current, (_) {}, null);
    for (final entity in ['PARENT_LINK', 'REPRODUCTIVE_EVENT']) {
      final local = newLocalUuid();
      String? prior;
      for (final action in ['CREATE', 'UPDATE', 'DELETE']) {
        final uuid = newLocalUuid();
        final parent = entity == 'PARENT_LINK';
        final payload = parent
            ? {'child_uuid': female, 'parent_uuid': male, 'role': 'FATHER'}
            : {
                'male_uuid': male,
                'female_uuid': female,
                'mating_date': '2026-11-13',
                'notes': 'Cría'
              };
        await db.customStatement("""
          INSERT INTO sync_operations
            (owner_id,operation_uuid,entity_type,rabbit_uuid,operation_type,payload,
             base_version,created_at,dependencies,entity_references)
          VALUES (?, ?, ?, ?, ?, ?, 0,'then',?,?)
        """, [
          owner,
          uuid,
          entity,
          local,
          action,
          jsonEncode(payload),
          jsonEncode([if (prior != null) prior]),
          jsonEncode([male, female])
        ]);
        if (!parent && action == 'DELETE') {
          fault.strip = true;
        } else {
          fault.drop = true;
        }
        if (!parent && action == 'CREATE') {
          fault.afterCommit = () => db.customStatement("""
            INSERT INTO local_reproductive_events
              (owner_id,uuid,male_uuid,female_uuid,mating_date,
               notes,version,created_at,updated_at)
            VALUES (?,?,?,?, '2026-11-13','edición posterior',2,'then','later')
          """, [owner, local, male, female]);
        }
        await drain();
        expect((await store.operation(uuid))?.status, 'SYNCING');
        final command = await store.frozenCommand(uuid);
        expect(command, isNotNull);
        if (parent && action == 'UPDATE') {
          await db.customStatement("""
            CREATE TRIGGER deny_result BEFORE INSERT ON sync_operation_results
            BEGIN SELECT RAISE(ABORT, 'injected'); END
          """);
          await db
              .customStatement('UPDATE sync_frozen_commands SET retry_at=0');
          await drain();
          expect((await store.operation(uuid))?.status, 'SYNCING');
          await db.customStatement('DROP TRIGGER deny_result');
        }
        await db.customStatement('UPDATE sync_frozen_commands SET retry_at=0');
        await drain();
        expect((await store.operation(uuid))?.status, 'COMPLETED');
        expect(await store.frozenCommand(uuid), command);
        prior = uuid;
      }
    }
    final results =
        await db.customSelect('SELECT * FROM sync_operation_results').get();
    expect(results, hasLength(6));
    final localEvent = await db.select(db.localReproductiveEvents).getSingle();
    expect(localEvent.notes, 'edición posterior');
    expect(localEvent.version, 2);
    expect(
        results
            .where((r) => r.read<int>('status_code') == 204)
            .single
            .readNullable<String>('response_json'),
        isNull);
    final identities =
        await db.customSelect('SELECT * FROM sync_identity_mappings').get();
    expect(identities, hasLength(2));
    // A server commit followed by logout cannot confirm the old attempt locally.
    final interrupted = newLocalUuid();
    await db.customStatement("""
      INSERT INTO sync_operations
        (owner_id,operation_uuid,entity_type,rabbit_uuid,operation_type,payload,
         base_version,created_at,entity_references)
      VALUES (?, ?, 'REPRODUCTIVE_EVENT', 'interrupted', 'CREATE', ?, 0,'then',?)
    """, [
      owner,
      interrupted,
      jsonEncode({
        'male_uuid': male,
        'female_uuid': female,
        'mating_date': '2026-11-13'
      }),
      jsonEncode([male, female])
    ]);
    fault.afterCommit = () async {
      current = false;
    };
    await drain();
    final foreign = SyncEvidenceStore(db,
        ownerId: owner + 1, generation: 2, isCurrent: () => true);
    await R3Publisher(client, foreign).drain(() async => true, (_) {}, null);
    expect(await db.customSelect('SELECT * FROM sync_operation_results').get(),
        hasLength(6));
    final resumed = SyncEvidenceStore(db,
        ownerId: owner, generation: 3, isCurrent: () => true);
    await R3Publisher(client, resumed).drain(() async => false, (_) {}, null);
    expect((await resumed.operation(interrupted))?.attempts, 1);
    await R3Publisher(client, resumed).drain(() async => true, (_) {}, null);
    expect((await resumed.operation(interrupted))?.status, 'COMPLETED');
    expect(
        identities
            .singleWhere((r) => r.read<String>('entity_type') == 'PARENT_LINK')
            .readNullable<String>('remote_entity_uuid'),
        isNull);
  }, skip: Platform.environment['E73_HTTP_FIXTURE'] == null);
}
