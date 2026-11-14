import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/data/local/r3_hydration.dart';
import 'package:frontend/data/local/sync_evidence_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const snapshot = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const first = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const second = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const male = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const female = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const instant = '2026-11-13T00:00:00Z';

Map<String, dynamic> event(String id,
        {int version = 1, String notes = '', bool deleted = false}) =>
    {
      'uuid': id,
      'male_uuid': male,
      'female_uuid': female,
      'mating_date': '2026-11-13',
      'notes': notes,
      'version': version,
      'created_at': instant,
      'updated_at': instant,
      'deleted_at': deleted ? instant : null,
    };

Map<String, dynamic> page(int ordinal,
        {int revision = 1,
        String id = snapshot,
        List<Map<String, dynamic>>? rows,
        int pages = 2}) =>
    {
      'snapshot_uuid': id,
      'owner_id': 1,
      'entity': 'REPRODUCTIVE_EVENT',
      'scope': {'from': null, 'to': null},
      'revision': revision,
      'cut': instant,
      'page': ordinal,
      'pages': pages,
      'total': pages == 1 ? rows!.length : 2,
      'next_cursor': ordinal + 1 < pages ? ordinal + 1 : null,
      'items':
          rows ?? [event(ordinal == 0 ? first : second, deleted: ordinal == 1)],
    };

void main() {
  test(
      'stages once and resumes after interruption with owner and generation guards',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    var current = true;
    final store = SyncEvidenceStore(db,
        ownerId: 1, generation: 1, isCurrent: () => current);
    var fail = true;
    final client = ApiClient(
        baseUrl: 'http://localhost',
        httpClient: MockClient((request) async {
          if (request.method == 'POST')
            return http.Response(jsonEncode(page(0)), 201);
          if (fail) return http.Response('{}', 503);
          return http.Response(jsonEncode(page(1)), 200);
        }));
    final hydration = R3Hydration(store, client);
    await expectLater(hydration.stage(page(1)), throwsFormatException);
    final id = await hydration.open('REPRODUCTIVE_EVENT');
    await hydration.stage(page(0));
    await expectLater(hydration.resume(id), throwsException);
    expect(
        (await db.customSelect('SELECT * FROM r3_hydrations').getSingle())
            .read<String>('state'),
        'PARTIAL');
    await expectLater(
        hydration.stage({...page(1), 'owner_id': 2}), throwsFormatException);
    current = false;
    await expectLater(hydration.stage(page(1)), throwsStateError);
    current = true;
    fail = false;
    await hydration.resume(id);
    await hydration.resume(id);
    final done =
        await db.customSelect('SELECT * FROM r3_hydrations').getSingle();
    expect(done.read<String>('state'), 'COMPLETE');
    expect(done.read<int>('received'), 2);
    expect(await db.select(db.localReproductiveEvents).get(), isEmpty);
  });
}
