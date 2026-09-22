import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/models/rabbit.dart';
import 'package:frontend/models/sync_operation.dart';
import 'package:frontend/models/sync_status.dart';
import 'package:frontend/services/connectivity_gate.dart';
import 'package:frontend/services/rabbit_local_store.dart';
import 'package:frontend/services/rabbit_service.dart';

Map<String, dynamic> _remote({
  required String uuid,
  required String name,
  int version = 1,
  double? weight = 2.0,
}) =>
    {
      'id': 42,
      'uuid': uuid,
      'user': 4,
      'name': name,
      'breed': 'Rex',
      'sex': 'female',
      'birth_date': '2024-06-01',
      'weight': weight,
      'status': 'active',
      'notes': '',
      'version': version,
      'created_at': '2024-06-01T00:00:00Z',
      'updated_at': '2024-06-01T00:00:00Z',
    };

const _luna = Rabbit(
  id: 7,
  uuid: '11111111-1111-1111-1111-111111111111',
  userId: 4,
  name: 'Luna',
  breed: 'Rex',
  sex: 'female',
  birthDate: '2024-01-15',
  weight: 2.5,
  status: 'active',
  notes: '',
  version: 1,
  createdAt: '2024-01-01T00:00:00Z',
  updatedAt: '2024-01-01T00:00:00Z',
);

RabbitService _service(
  AppDatabase db,
  http.Client httpClient, {
  ConnectivityGate? connectivity,
}) {
  return RabbitService(
    ApiClient(httpClient: httpClient),
    RabbitLocalStore(db),
    connectivity: connectivity ?? FakeConnectivity(online: true),
  );
}

void main() {
  test('syncPending POSTs queued CREATE and marks the rabbit SYNCED', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    var postCount = 0;
    final service = _service(
      db,
      MockClient((req) async {
        if (req.method == 'POST') {
          postCount += 1;
          if (postCount == 1) return http.Response('sin servidor', 500);
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['uuid'], isNotEmpty);
          return http.Response(
            jsonEncode(_remote(uuid: body['uuid'] as String, name: 'Nube')),
            201,
          );
        }
        return http.Response('[]', 200);
      }),
    );

    final created = await service.createRabbit(
      name: 'Nube',
      breed: 'Rex',
      sex: 'female',
      birthDate: '2024-06-01',
      status: 'active',
      weight: 2.0,
    );
    expect(created.syncStatus, RabbitSyncStatus.pendingCreate);

    await service.syncPending();

    expect(postCount, 2);
    expect(await service.readPendingOperations(), isEmpty);
    final local = await service.readLocalRabbits();
    expect(local.single.uuid, created.uuid);
    expect(local.single.id, 42);
    expect(local.single.syncStatus, RabbitSyncStatus.synced);
  });

  test('syncPending PUTs queued UPDATE', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await RabbitLocalStore(db).persistSynced([_luna]);
    var putCount = 0;
    final service = _service(
      db,
      MockClient((req) async {
        if (req.method == 'PUT') {
          putCount += 1;
          if (putCount == 1) return http.Response('sin servidor', 500);
          return http.Response(
            jsonEncode(_remote(uuid: _luna.uuid, name: 'Luna', weight: 3.1, version: 2)),
            200,
          );
        }
        return http.Response('[]', 200);
      }),
    );

    await service.updateRabbit(
      uuid: _luna.uuid,
      name: 'Luna',
      breed: 'Rex',
      sex: 'female',
      birthDate: '2024-01-15',
      weight: 3.1,
      status: 'active',
    );
    await service.syncPending();

    expect(putCount, 2);
    expect(await service.readPendingOperations(), isEmpty);
    expect((await service.readLocalRabbits()).single.syncStatus, RabbitSyncStatus.synced);
    expect((await service.readLocalRabbits()).single.weight, 3.1);
  });

  test('syncPending DELETEs queued removal', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await RabbitLocalStore(db).persistSynced([_luna]);
    var deleteCount = 0;
    final service = _service(
      db,
      MockClient((req) async {
        if (req.method == 'DELETE') {
          deleteCount += 1;
          if (deleteCount == 1) return http.Response('sin servidor', 500);
          return http.Response('', 204);
        }
        return http.Response('[]', 200);
      }),
    );

    await service.deleteRabbit(_luna.uuid);
    expect(await service.readLocalRabbits(), isEmpty);
    await service.syncPending();

    expect(deleteCount, 2);
    expect(await service.readPendingOperations(), isEmpty);
  });

  test('failed sync keeps the operation, records error and retries later', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    var postCount = 0;
    final service = _service(
      db,
      MockClient((req) async {
        if (req.method == 'POST') {
          postCount += 1;
          return http.Response('sin servidor', 500);
        }
        return http.Response('[]', 200);
      }),
    );

    await service.createRabbit(
      name: 'Nube',
      breed: 'Rex',
      sex: 'female',
      birthDate: '2024-06-01',
      status: 'active',
    );
    await service.syncPending();

    final failed = await service.readRetryableOperations();
    expect(failed, hasLength(1));
    expect(failed.single.status, SyncOpStatus.failed);
    expect(failed.single.attempts, greaterThanOrEqualTo(1));
    expect(failed.single.lastError, isNotEmpty);
    expect(postCount, 2);

    await service.syncPending();
    expect(postCount, 3);
    expect((await service.readRetryableOperations()).single.attempts, greaterThanOrEqualTo(2));
  });

  test('CREATE is idempotent when the UUID already exists on the server', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    var postCount = 0;
    final service = _service(
      db,
      MockClient((req) async {
        if (req.method == 'POST') {
          postCount += 1;
          if (postCount == 1) return http.Response('sin servidor', 500);
          return http.Response(jsonEncode({'uuid': ['already exists']}), 400);
        }
        if (req.method == 'GET') {
          final segs =
              req.url.path.split('/').where((s) => s.isNotEmpty).toList();
          if (segs.length >= 3) {
            return http.Response(
              jsonEncode(_remote(uuid: segs[2], name: 'Nube')),
              200,
            );
          }
          return http.Response('[]', 200);
        }
        return http.Response('nope', 405);
      }),
    );

    final created = await service.createRabbit(
      name: 'Nube',
      breed: 'Rex',
      sex: 'female',
      birthDate: '2024-06-01',
      status: 'active',
    );
    await service.syncPending();

    expect(await service.readPendingOperations(), isEmpty);
    expect((await service.readLocalRabbits()).single.uuid, created.uuid);
    expect((await service.readLocalRabbits()).single.syncStatus, RabbitSyncStatus.synced);
  });

  test('syncPending does not call the API when connectivity is offline', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    var calls = 0;
    final service = _service(
      db,
      MockClient((req) async {
        calls += 1;
        return http.Response('sin servidor', 500);
      }),
      connectivity: FakeConnectivity(online: false),
    );

    await service.createRabbit(
      name: 'Nube',
      breed: 'Rex',
      sex: 'female',
      birthDate: '2024-06-01',
      status: 'active',
    );
    final afterCreate = calls;
    await service.syncPending();
    expect(calls, afterCreate);
    expect(await service.readPendingOperations(), hasLength(1));
  });
}
