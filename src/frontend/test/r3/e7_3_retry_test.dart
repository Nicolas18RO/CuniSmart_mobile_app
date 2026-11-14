import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/data/local/sync_evidence_store.dart';
import 'package:frontend/services/r3_publisher.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final status in [401, 403, 404, 422, 429, 500]) {
    test('publication handles HTTP $status and preserves the frozen command',
        () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await db.customStatement("""
        INSERT INTO rabbits (uuid,user_id,server_id,name,breed,sex,birth_date,status,created_at,updated_at)
        VALUES ('m',1,1,'Male','rex','male','2024-01-01','active','then','then'),
               ('f',1,2,'Female','rex','female','2024-01-01','active','then','then')
      """);
      await db.customStatement("""
        INSERT INTO sync_operations
          (owner_id,operation_uuid,entity_type,rabbit_uuid,operation_type,payload,
           base_version,created_at,entity_references)
        VALUES (1,'op','REPRODUCTIVE_EVENT','local','CREATE',
          '{"male_uuid":"m","female_uuid":"f","mating_date":"2026-11-13"}',
          0,'then','["m","f"]')
      """);
      var sends = 0;
      var verifications = 0;
      final client = ApiClient(
          baseUrl: 'http://localhost',
          httpClient: MockClient((request) async {
            sends++;
            expect(request.headers['Idempotency-Key'], 'op');
            expect(jsonDecode(request.body)['mating_date'], '2026-11-13');
            return http.Response('{}', status, headers: {'Retry-After': '90'});
          }));
      final store = SyncEvidenceStore(db,
          ownerId: 1, generation: 1, isCurrent: () => true);
      final publisher = R3Publisher(client, store);
      final delays = <Duration>[];
      Future<void> drain() =>
          publisher.drain(() async => true, delays.add, () async {
            verifications++;
            return true;
          });
      await drain();
      final command = await store.frozenCommand('op');
      final retry = [401, 429, 500].contains(status);
      expect(
          (await store.operation('op'))?.status, retry ? 'SYNCING' : 'FAILED');
      expect(verifications, status == 401 ? 1 : 0);
      if (status == 429) expect(delays.first.inSeconds, 90);
      if (retry) {
        await drain();
        expect(sends, 1);
        for (var i = 0; i < 5; i++) {
          await db
              .customStatement('UPDATE sync_frozen_commands SET retry_at=0');
          await drain();
        }
      }
      expect(sends, retry ? 5 : 1);
      expect((await store.operation('op'))?.status, 'FAILED');
      expect(await store.frozenCommand('op'), command);
    });
  }
}
