import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/models/rabbit.dart';
import 'package:frontend/models/sync_operation.dart';
import 'package:frontend/models/sync_status.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/auth_token_storage.dart';
import 'package:frontend/services/connectivity_gate.dart';
import 'package:frontend/services/rabbit_local_store.dart';
import 'package:frontend/services/rabbit_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

Rabbit rabbit(String uuid, int owner) => Rabbit(
      id: owner,
      uuid: uuid,
      userId: owner,
      name: uuid,
      breed: 'rex',
      sex: 'male',
      birthDate: '2024-01-01',
      status: 'active',
      notes: '',
      version: 1,
      createdAt: '2025-01-01',
      updatedAt: '2025-01-01',
    );

void main() {
  for (final version in [1, 2, 3]) {
    test('v$version migration preserves rows and quarantines ownerless work',
        () async {
      final dir = await Directory.systemTemp.createTemp('cunismart_e61_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/test.sqlite');
      final legacy = sqlite.sqlite3.open(file.path);
      legacy.execute('''
        CREATE TABLE rabbits (
          uuid TEXT NOT NULL PRIMARY KEY, server_id INTEGER, user_id INTEGER NOT NULL,
          name TEXT NOT NULL, breed TEXT NOT NULL, sex TEXT NOT NULL, birth_date TEXT NOT NULL,
          weight REAL, status TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
          version INTEGER NOT NULL DEFAULT 1, deleted_at TEXT,
          sync_status TEXT NOT NULL DEFAULT 'SYNCED'
          ${version == 3 ? ", genealogy_knowledge TEXT NOT NULL DEFAULT 'UNKNOWN'" : ''}
        )
      ''');
      if (version >= 2) {
        legacy.execute('''
          CREATE TABLE sync_operations (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, rabbit_uuid TEXT NOT NULL,
            operation_type TEXT NOT NULL, payload TEXT NOT NULL, base_version INTEGER NOT NULL,
            created_at TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'PENDING', last_error TEXT, server_snapshot TEXT
          )
        ''');
        legacy.execute("""
          INSERT INTO sync_operations (rabbit_uuid, operation_type, payload, base_version, created_at, status)
          VALUES ('known','UPDATE','{"retained":true}',7,'original','SYNCING'),
                 ('orphan','DELETE','{}',1,'original','FAILED')
        """);
      }
      legacy.execute("""
        INSERT INTO rabbits (uuid,user_id,name,breed,sex,birth_date,status,created_at,updated_at)
        VALUES ('known',1,'Known','rex','male','2024-01-01','active','original','original'),
               ('unknown',0,'Unknown','rex','male','2024-01-01','active','original','original')
      """);
      if (version == 3) {
        legacy.execute(
            "UPDATE rabbits SET genealogy_knowledge = 'FOUNDER' WHERE uuid = 'known'");
      }
      legacy.userVersion = version;
      legacy.dispose();

      for (var reopen = 0; reopen < 2; reopen++) {
        final db = AppDatabase.file(file);
        try {
          final owner = RabbitLocalStore(db).forOwner(1, () => true);
          final known = (await owner.readActive()).single;
          expect(known.uuid, 'known');
          expect(
              known.genealogyKnowledge, version == 3 ? 'FOUNDER' : 'UNKNOWN');
          expect(await owner.readRetryableOperations(), isEmpty);
          final allRabbits = await db.select(db.rabbits).get();
          expect(
              allRabbits
                  .singleWhere((r) => r.uuid == 'unknown')
                  .quarantineReason,
              'legacy:unknown_owner');
          final rows = await db.select(db.syncOperations).get();
          expect(rows, hasLength(version >= 2 ? 2 : 0));
          if (version >= 2) {
            expect(rows.first.payload, '{"retained":true}');
            expect(rows.first.status, 'SYNCING');
            expect(rows.first.baseVersion, 7);
            expect(
                rows.every((row) =>
                    row.ownerId == null &&
                    row.quarantineReason == 'legacy:unproven_owner'),
                isTrue);
          }
        } finally {
          await db.close();
        }
      }
    });
  }

  test('owners isolate reads, writes, snapshots, tombstones and conflict queue',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final local = RabbitLocalStore(db);
    final a = local.forOwner(1, () => true);
    final b = local.forOwner(2, () => true);
    await a.upsert(rabbit('a', 1));
    await b.upsert(rabbit('b', 2));
    expect((await a.readActive()).single.uuid, 'a');
    expect((await b.readActive()).single.uuid, 'b');
    expect(await b.readByUuid('a'), isNull);
    await expectLater(b.upsert(rabbit('a', 2)), throwsException);
    await b.markDeleted('a', status: RabbitSyncStatus.pendingDelete);
    await b.removeByUuid('a');
    await b.persistSynced([]);
    expect((await a.readActive()).single.uuid, 'a');
    expect(await b.readActive(), isEmpty);
    await a.enqueueOrCoalesce(
        rabbitUuid: 'a',
        type: SyncOperationType.update,
        payload: '{"name":"A"}',
        baseVersion: 1);
    final op = (await a.readPendingOperations()).single;
    await a.markOperation(
        id: op.id, status: SyncOpStatus.conflict, serverSnapshot: '{}');
    await b.markOperation(id: op.id, status: SyncOpStatus.completed);
    expect(await b.readConflictForUuid('a'), isNull);
    expect((await a.readConflictOperations()).single.id, op.id);
    expect((await db.select(db.syncOperations).get()).single.operationUuid,
        isNotNull);
  });

  test('atomic transaction rolls back when session changes mid-write',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    var current = true;
    final a = RabbitLocalStore(db).forOwner(1, () => current);
    await expectLater(a.transaction(() async {
      await a.upsert(rabbit('a', 1));
      await a.enqueueOrCoalesce(
          rabbitUuid: 'a',
          type: SyncOperationType.create,
          payload: '{}',
          baseVersion: 1);
      current = false;
    }), throwsException);
    expect(await db.select(db.rabbits).get(), isEmpty);
    expect(await db.select(db.syncOperations).get(), isEmpty);
  });

  test(
      'E6.1-12 queues offline, verifies before send and ignores late reply across accounts',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final connection = FakeConnectivity(online: true);
    addTearDown(connection.close);
    final sent = <String>[];
    final posted = Completer<void>();
    final reply = Completer<http.Response>();
    var owner = 1;
    var refreshStatus = 200;
    final api = ApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient((request) async {
          sent.add(request.url.path);
          switch (request.url.path) {
            case '/api/auth/login/':
            case '/api/auth/token/refresh/':
              return http.Response(
                  '{"access":"access-$owner","refresh":"refresh-$owner"}',
                  request.url.path.endsWith('refresh/') ? refreshStatus : 200);
            case '/api/auth/session/':
              expect(request.headers['Authorization'], 'Bearer access-$owner');
              return http.Response(
                  jsonEncode({
                    'user': {'id': owner, 'is_verified': true},
                    'settings': {'biometric_enabled': false},
                  }),
                  200);
            case '/api/rabbits/':
              expect(request.headers['Authorization'], 'Bearer access-1');
              posted.complete();
              return reply.future;
            default:
              fail('Unexpected request ${request.url.path}');
          }
        }));
    final auth = AuthService(
        apiClient: api,
        tokenStorage: AuthTokenStorage.inMemory(),
        readBootTime: () async =>
            (bootCount: 1, elapsedMilliseconds: 0, installationId: 'test'));
    addTearDown(() => auth.clearSession(notify: false));
    api.sessionGeneration = () => auth.generation;
    final store = RabbitLocalStore(db);
    final service =
        RabbitService(api, store, auth: auth, connectivity: connection);
    await auth.login(email: 'a@test.invalid', password: 'pw');
    auth.localDataUnlocked = true;

    connection.online = false;
    final created = await service.createRabbit(
        name: 'A',
        breed: 'rex',
        sex: 'male',
        birthDate: '2024-01-01',
        status: 'active');
    expect(created.userId, 1);
    expect(sent, isNot(contains('/api/rabbits/')));
    connection.online = true;
    refreshStatus = 503;
    await service.syncPending();
    expect(sent, isNot(contains('/api/rabbits/')));
    refreshStatus = 200;
    final draining = service.syncPending();
    final aborted = expectLater(draining, throwsException);
    await posted.future;
    expect(sent.sublist(sent.length - 3), [
      '/api/auth/token/refresh/',
      '/api/auth/session/',
      '/api/rabbits/',
    ]);

    owner = 2;
    await auth.login(email: 'b@test.invalid', password: 'pw');
    auth.localDataUnlocked = true;
    reply.complete(http.Response('{"uuid":"${created.uuid}","user":1}', 200));
    await aborted;
    expect(await service.readLocalRabbits(), isEmpty);
    expect(await service.readRetryableOperations(), isEmpty);
    await service.syncPending();
    await expectLater(service.resolveConflictKeepLocal(created.uuid), throwsException);
    expect(sent.where((path) => path == '/api/rabbits/'), hasLength(1));
    final old = store.forOwner(1, () => true);
    expect((await old.readByUuid(created.uuid))!.syncStatus,
        RabbitSyncStatus.pendingCreate);
    expect(await old.readRetryableOperations(), hasLength(1));
  });
}
