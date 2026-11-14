import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/models/sync_operation.dart';
import 'package:frontend/services/rabbit_local_store.dart';

void main() {
  for (final failure in [
    'marker',
    'preserve',
    'queue',
    'rabbit',
    'commit',
    'none'
  ]) {
    test('cancellation is atomic at $failure', () async {
      final dir = await Directory.systemTemp.createTemp('cunismart_cancel_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/test.sqlite');
      final db = AppDatabase.file(file);
      await db.customStatement("""
        INSERT INTO rabbits
          (uuid,user_id,name,breed,sex,birth_date,status,created_at,updated_at)
        VALUES ('rabbit',1,'Rabbit','rex','male','2024-01-01','active','then','then')
      """);
      await db.customStatement("""
        INSERT INTO sync_operations
          (owner_id,operation_uuid,entity_type,rabbit_uuid,operation_type,payload,
           base_version,created_at,dependencies,entity_references)
        VALUES (1,'create','RABBIT','rabbit','CREATE','{}',0,'then','[]','[]'),
               (1,'event','REPRODUCTIVE_EVENT','event','CREATE','{"kept":true}',
                0,'then','["create"]','["rabbit"]')
      """);
      if (failure == 'marker' || failure == 'queue' || failure == 'rabbit') {
        final event = switch (failure) {
          'marker' => 'INSERT ON sync_create_cancellations',
          'queue' => 'DELETE ON sync_operations',
          _ => 'DELETE ON rabbits',
        };
        await db.customStatement("""
          CREATE TRIGGER inject_failure BEFORE $event
          BEGIN SELECT RAISE(ABORT, 'injected'); END
        """);
      }
      final store = RabbitLocalStore(db, ownerId: 1);
      var checks = 0;
      Future<void> cancel() => store.transaction(() async {
            if (failure == 'preserve') {
              // Abort from the session guard immediately after the marker is written.
              final scoped = RabbitLocalStore(db, ownerId: 1, isCurrent: () {
                return ++checks < 3;
              });
              await scoped.enqueueOrCoalesce(
                  rabbitUuid: 'rabbit',
                  type: SyncOperationType.delete,
                  payload: '{}',
                  baseVersion: 1);
            } else {
              await store.enqueueOrCoalesce(
                  rabbitUuid: 'rabbit',
                  type: SyncOperationType.delete,
                  payload: '{}',
                  baseVersion: 1);
            }
            if (failure == 'commit') throw StateError('injected');
          });
      if (failure == 'none') {
        await cancel();
      } else {
        await expectLater(cancel(), throwsA(anything));
      }
      await db.close();

      final reopened = AppDatabase.file(file);
      try {
        final markers = await reopened
            .customSelect('SELECT * FROM sync_create_cancellations')
            .get();
        final rows = await reopened.select(reopened.syncOperations).get();
        final event = rows.singleWhere((row) => row.operationUuid == 'event');
        expect(event.payload, '{"kept":true}');
        expect(event.dependencies, '["create"]');
        expect(event.entityReferences, '["rabbit"]');
        final rabbits = await reopened.select(reopened.rabbits).get();
        if (failure == 'none') {
          expect(markers.single.read<String>('operation_uuid'), 'create');
          expect(rows, hasLength(1));
          expect(rabbits, isEmpty);
        } else {
          expect(markers, isEmpty);
          expect(rows, hasLength(2));
          expect(rabbits.single.uuid, 'rabbit');
        }
      } finally {
        await reopened.close();
      }
    });
  }
}
