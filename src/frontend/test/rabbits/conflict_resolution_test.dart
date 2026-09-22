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

Map<String, dynamic> _remote({
  required String notes,
  required int version,
}) =>
    {
      'id': 7,
      'uuid': _luna.uuid,
      'user': 4,
      'name': 'Luna',
      'breed': 'Rex',
      'sex': 'female',
      'birth_date': '2024-01-15',
      'weight': 2.5,
      'status': 'active',
      'notes': notes,
      'version': version,
      'created_at': '2024-01-01T00:00:00Z',
      'updated_at': '2024-01-01T00:00:00Z',
    };

RabbitService _service(AppDatabase db, http.Client client) {
  return RabbitService(
    ApiClient(httpClient: client),
    RabbitLocalStore(db),
    connectivity: FakeConnectivity(online: true),
  );
}

void main() {
  test('stale UPDATE becomes CONFLICT and keeps the remote snapshot', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await RabbitLocalStore(db).persistSynced([_luna]);
    var puts = 0;
    final service = _service(
      db,
      MockClient((req) async {
        if (req.method == 'PUT') {
          puts += 1;
          if (puts == 1) return http.Response('sin servidor', 500);
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['version'], 1);
          return http.Response(
            jsonEncode({
              'detail': {
                'code': 'version_conflict',
                'message': 'El conejo fue modificado en otro lugar.',
                'current': _remote(notes: 'servidor', version: 2),
              },
            }),
            409,
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
      weight: 2.5,
      status: 'active',
      notes: 'telefono',
    );
    await service.syncPending();

    expect(await service.readPendingOperations(), isEmpty);
    final retryable = await service.readRetryableOperations();
    expect(retryable, isEmpty);
    final conflicts = await service.readConflictOperations();
    expect(conflicts, hasLength(1));
    expect(conflicts.single.status, SyncOpStatus.conflict);
    expect(conflicts.single.serverSnapshot, contains('servidor'));
    final local = await service.readLocalRabbits();
    expect(local.single.notes, 'telefono');
    expect(local.single.syncStatus, RabbitSyncStatus.conflict);
  });

  test('keep remote applies the snapshot and clears the conflict', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await RabbitLocalStore(db).persistSynced([_luna]);
    var puts = 0;
    final service = _service(
      db,
      MockClient((req) async {
        if (req.method == 'PUT') {
          puts += 1;
          if (puts == 1) return http.Response('sin servidor', 500);
          return http.Response(
            jsonEncode({
              'detail': {
                'code': 'version_conflict',
                'message': 'El conejo fue modificado en otro lugar.',
                'current': _remote(notes: 'servidor', version: 2),
              },
            }),
            409,
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
      weight: 2.5,
      status: 'active',
      notes: 'telefono',
    );
    await service.syncPending();
    await service.resolveConflictKeepRemote(_luna.uuid);

    expect(await service.readConflictOperations(), isEmpty);
    final local = await service.readLocalRabbits();
    expect(local.single.notes, 'servidor');
    expect(local.single.version, 2);
    expect(local.single.syncStatus, RabbitSyncStatus.synced);
  });

  test('keep local retries PUT with the remote version', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await RabbitLocalStore(db).persistSynced([_luna]);
    final versions = <int?>[];
    var puts = 0;
    final service = _service(
      db,
      MockClient((req) async {
        if (req.method == 'PUT') {
          puts += 1;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          versions.add((body['version'] as num?)?.toInt());
          if (puts == 1) return http.Response('sin servidor', 500);
          if (puts == 2) {
            return http.Response(
              jsonEncode({
                'detail': {
                  'code': 'version_conflict',
                  'current': _remote(notes: 'servidor', version: 2),
                },
              }),
              409,
            );
          }
          expect(body['notes'], 'telefono');
          expect(body['version'], 2);
          return http.Response(
            jsonEncode(_remote(notes: 'telefono', version: 3)),
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
      weight: 2.5,
      status: 'active',
      notes: 'telefono',
    );
    await service.syncPending();
    await service.resolveConflictKeepLocal(_luna.uuid);

    expect(versions, containsAll([1, 2]));
    expect(await service.readConflictOperations(), isEmpty);
    final local = await service.readLocalRabbits();
    expect(local.single.notes, 'telefono');
    expect(local.single.version, 3);
    expect(local.single.syncStatus, RabbitSyncStatus.synced);
  });
}
