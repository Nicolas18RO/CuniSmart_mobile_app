import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/state/async_view_state.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/models/rabbit.dart';
import 'package:frontend/models/sync_operation.dart';
import 'package:frontend/models/sync_status.dart';
import 'package:frontend/services/rabbit_local_store.dart';
import 'package:frontend/services/rabbit_service.dart';
import 'package:frontend/viewmodels/rabbit_viewmodel.dart';

http.Client _down() => MockClient((_) async => http.Response('sin servidor', 500));

RabbitService _offlineService(AppDatabase db) {
  return RabbitService(
    ApiClient(httpClient: _down()),
    RabbitLocalStore(db),
  );
}

void main() {
  test('create without server saves PENDING_CREATE and a CREATE queue row', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final service = _offlineService(db);

    final created = await service.createRabbit(
      name: 'Nube',
      breed: 'Rex',
      sex: 'female',
      birthDate: '2024-06-01',
      status: 'active',
    );

    expect(created.uuid, isNotEmpty);
    expect(created.syncStatus, RabbitSyncStatus.pendingCreate);
    final local = await service.readLocalRabbits();
    expect(local.single.name, 'Nube');
    final ops = await service.readPendingOperations();
    expect(ops, hasLength(1));
    expect(ops.single.operationType, SyncOperationType.create);
    expect(ops.single.status, SyncOpStatus.pending);
    expect(ops.single.rabbitUuid, created.uuid);
  });

  test('queue survives close and reopen of the database file', () async {
    final dir = await Directory.systemTemp.createTemp('cunismart_r25_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'cunismart.sqlite'));

    final db1 = AppDatabase.file(file);
    final created = await _offlineService(db1).createRabbit(
      name: 'Nube',
      breed: 'Rex',
      sex: 'female',
      birthDate: '2024-06-01',
      status: 'active',
    );
    await db1.close();

    final db2 = AppDatabase.file(file);
    addTearDown(db2.close);
    final ops = await _offlineService(db2).readPendingOperations();
    expect(ops, hasLength(1));
    expect(ops.single.rabbitUuid, created.uuid);
    expect(ops.single.operationType, SyncOperationType.create);
    final local = await RabbitLocalStore(db2).readActive();
    expect(local.single.name, 'Nube');
  });

  test('update without server writes PENDING_UPDATE and keeps the animal visible', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final store = RabbitLocalStore(db);
    await store.persistSynced([
      const Rabbit(
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
      ),
    ]);
    final service = _offlineService(db);

    final updated = await service.updateRabbit(
      uuid: '11111111-1111-1111-1111-111111111111',
      name: 'Luna',
      breed: 'Rex',
      sex: 'female',
      birthDate: '2024-01-15',
      weight: 3.1,
      status: 'active',
    );

    expect(updated.weight, 3.1);
    expect(updated.syncStatus, RabbitSyncStatus.pendingUpdate);
    expect((await service.readLocalRabbits()).single.weight, 3.1);
    final ops = await service.readPendingOperations();
    expect(ops.single.operationType, SyncOperationType.update);
  });

  test('delete without server hides the animal and enqueues DELETE', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await RabbitLocalStore(db).persistSynced([
      const Rabbit(
        id: 7,
        uuid: '11111111-1111-1111-1111-111111111111',
        userId: 4,
        name: 'Luna',
        breed: 'Rex',
        sex: 'female',
        birthDate: '2024-01-15',
        status: 'active',
        notes: '',
        version: 1,
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-01T00:00:00Z',
      ),
    ]);
    final service = _offlineService(db);

    await service.deleteRabbit('11111111-1111-1111-1111-111111111111');

    expect(await service.readLocalRabbits(), isEmpty);
    final ops = await service.readPendingOperations();
    expect(ops.single.operationType, SyncOperationType.delete);
  });

  test('unsynced create then delete cancels the queue instead of DELETE', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final service = _offlineService(db);
    final created = await service.createRabbit(
      name: 'Nube',
      breed: 'Rex',
      sex: 'female',
      birthDate: '2024-06-01',
      status: 'active',
    );

    await service.deleteRabbit(created.uuid);

    expect(await service.readLocalRabbits(), isEmpty);
    expect(await service.readPendingOperations(), isEmpty);
  });

  test('ViewModel createRabbit succeeds when the API is down', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final vm = RabbitViewModel(_offlineService(db));

    final ok = await vm.createRabbit(
      name: 'Nube',
      breed: 'Rex',
      sex: 'female',
      birthDate: '2024-06-01',
      status: 'active',
    );

    expect(ok, isTrue);
    final list = switch (vm.listState) {
      AsyncSuccess<List<Rabbit>>(:final data) => data,
      _ => <Rabbit>[],
    };
    expect(list.single.name, 'Nube');
    expect(list.single.syncStatus, RabbitSyncStatus.pendingCreate);
  });

  test('fetchRabbits does not wipe a pending local create', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final store = RabbitLocalStore(db);
    var calls = 0;
    final service = RabbitService(
      ApiClient(
        httpClient: MockClient((_) async {
          calls += 1;
          if (calls == 1) {
            return http.Response('sin servidor', 500);
          }
          return http.Response(
            jsonEncode([
              {
                'id': 7,
                'uuid': '11111111-1111-1111-1111-111111111111',
                'user': 4,
                'name': 'Luna',
                'breed': 'Rex',
                'sex': 'female',
                'birth_date': '2024-01-15',
                'weight': 2.5,
                'status': 'active',
                'notes': '',
                'version': 1,
                'created_at': '2024-01-01T00:00:00Z',
                'updated_at': '2024-01-01T00:00:00Z',
              },
            ]),
            200,
          );
        }),
      ),
      store,
    );

    await service.createRabbit(
      name: 'Nube',
      breed: 'Rex',
      sex: 'female',
      birthDate: '2024-06-01',
      status: 'active',
    );
    final afterFetch = await service.fetchRabbits();
    final names = afterFetch.map((r) => r.name).toSet();
    expect(names, containsAll(['Luna', 'Nube']));
  });
}
