import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/state/async_view_state.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/models/rabbit.dart';
import 'package:frontend/models/sync_status.dart';
import 'package:frontend/services/rabbit_local_store.dart';
import 'package:frontend/services/rabbit_service.dart';
import 'package:frontend/viewmodels/rabbit_viewmodel.dart';

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
  notes: 'Mansa',
  version: 1,
  createdAt: '2024-01-01T00:00:00Z',
  updatedAt: '2024-01-01T00:00:00Z',
  syncStatus: RabbitSyncStatus.synced,
);

Map<String, dynamic> _lunaJson() => {
      'id': _luna.id,
      'uuid': _luna.uuid,
      'user': _luna.userId,
      'name': _luna.name,
      'breed': _luna.breed,
      'sex': _luna.sex,
      'birth_date': _luna.birthDate,
      'weight': _luna.weight,
      'status': _luna.status,
      'notes': _luna.notes,
      'version': _luna.version,
      'created_at': _luna.createdAt,
      'updated_at': _luna.updatedAt,
    };

void main() {
  test('persists rabbits and reads them back with SYNCED status', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final store = RabbitLocalStore(db);

    await store.persistSynced([_luna]);
    final rows = await store.readActive();

    expect(rows, hasLength(1));
    expect(rows.single.uuid, _luna.uuid);
    expect(rows.single.name, 'Luna');
    expect(rows.single.id, 7);
    expect(rows.single.syncStatus, RabbitSyncStatus.synced);
  });

  test('survives close and reopen of the database file', () async {
    final dir = await Directory.systemTemp.createTemp('cunismart_r24_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'cunismart.sqlite'));

    final db1 = AppDatabase.file(file);
    await RabbitLocalStore(db1).persistSynced([_luna]);
    await db1.close();

    final db2 = AppDatabase.file(file);
    addTearDown(db2.close);
    final rows = await RabbitLocalStore(db2).readActive();

    expect(rows, hasLength(1));
    expect(rows.single.name, 'Luna');
    expect(rows.single.uuid, _luna.uuid);
    expect(rows.single.syncStatus, RabbitSyncStatus.synced);
  });

  test('schema 2 upgrades existing rabbits to UNKNOWN without data loss',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('cunismart_r3_migration_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'cunismart.sqlite'));
    final legacy = sqlite.sqlite3.open(file.path);
    legacy.execute('''
      CREATE TABLE rabbits (
        uuid TEXT NOT NULL PRIMARY KEY,
        server_id INTEGER NULL,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        breed TEXT NOT NULL,
        sex TEXT NOT NULL,
        birth_date TEXT NOT NULL,
        weight REAL NULL,
        status TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        deleted_at TEXT NULL,
        sync_status TEXT NOT NULL DEFAULT 'SYNCED'
      )
    ''');
    legacy.execute('''
      CREATE TABLE sync_operations (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        rabbit_uuid TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        base_version INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'PENDING',
        last_error TEXT NULL,
        server_snapshot TEXT NULL
      )
    ''');
    legacy.execute(
      'INSERT INTO rabbits (uuid, server_id, user_id, name, breed, sex, '
      'birth_date, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        _luna.uuid,
        _luna.id,
        _luna.userId,
        _luna.name,
        _luna.breed,
        _luna.sex,
        _luna.birthDate,
        _luna.status,
        _luna.createdAt,
        _luna.updatedAt
      ],
    );
    legacy.userVersion = 2;
    legacy.dispose();

    final db = AppDatabase.file(file);
    addTearDown(db.close);
    final rows = await RabbitLocalStore(db).readActive();

    expect(rows.single.name, 'Luna');
    expect(rows.single.genealogyKnowledge, 'UNKNOWN');
  });

  test('readActive hides logically deleted rabbits', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final store = RabbitLocalStore(db);
    await store.persistSynced([
      Rabbit(
        id: _luna.id,
        uuid: _luna.uuid,
        userId: _luna.userId,
        name: _luna.name,
        breed: _luna.breed,
        sex: _luna.sex,
        birthDate: _luna.birthDate,
        weight: _luna.weight,
        status: _luna.status,
        notes: _luna.notes,
        version: 2,
        createdAt: _luna.createdAt,
        updatedAt: _luna.updatedAt,
        deletedAt: '2026-09-21T12:00:00Z',
        syncStatus: RabbitSyncStatus.synced,
      ),
    ]);

    expect(await store.readActive(), isEmpty);
  });

  test('fetchRabbits writes remote animals to Drift', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final service = RabbitService(
      ApiClient(
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode([_lunaJson()]), 200),
        ),
      ),
      RabbitLocalStore(db),
    );

    final remote = await service.fetchRabbits();
    expect(remote.single.name, 'Luna');

    final local = await service.readLocalRabbits();
    expect(local.single.uuid, _luna.uuid);
    expect(local.single.syncStatus, RabbitSyncStatus.synced);
  });

  test('loadRabbits shows local data when API is down after reopen', () async {
    final dir = await Directory.systemTemp.createTemp('cunismart_r24_vm_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'cunismart.sqlite'));

    final db1 = AppDatabase.file(file);
    var vm = RabbitViewModel(
      RabbitService(
        ApiClient(
          httpClient: MockClient(
            (_) async => http.Response(jsonEncode([_lunaJson()]), 200),
          ),
        ),
        RabbitLocalStore(db1),
      ),
    );
    await vm.loadRabbits();
    await db1.close();

    final db2 = AppDatabase.file(file);
    addTearDown(db2.close);
    vm = RabbitViewModel(
      RabbitService(
        ApiClient(
          httpClient: MockClient(
            (_) async => http.Response('sin red', 500),
          ),
        ),
        RabbitLocalStore(db2),
      ),
    );
    await vm.loadRabbits();

    final list = switch (vm.listState) {
      AsyncSuccess<List<Rabbit>>(:final data) => data,
      AsyncError<List<Rabbit>>(:final cachedData) => cachedData,
      _ => null,
    };
    expect(list, isNotNull);
    expect(list!.single.name, 'Luna');
  });
}
