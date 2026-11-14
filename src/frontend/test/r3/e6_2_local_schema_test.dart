import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('v4 upgrade adds both R3 tables and preserves quarantined operations',
      () async {
    final dir = await Directory.systemTemp.createTemp('cunismart_e62_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/test.sqlite');
    // Frozen v4 fixture. Keep independent of the current schema generator.
    final legacy = sqlite.sqlite3.open(file.path);
    legacy.execute('''
      CREATE TABLE rabbits (
        uuid TEXT NOT NULL PRIMARY KEY, server_id INTEGER, user_id INTEGER NOT NULL,
        quarantine_reason TEXT, name TEXT NOT NULL, breed TEXT NOT NULL, sex TEXT NOT NULL,
        birth_date TEXT NOT NULL, weight REAL, status TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
        genealogy_knowledge TEXT NOT NULL DEFAULT 'UNKNOWN', created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1, deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'SYNCED'
      );
      CREATE TABLE sync_operations (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, owner_id INTEGER,
        operation_uuid TEXT, entity_type TEXT NOT NULL DEFAULT 'RABBIT',
        dependencies TEXT NOT NULL DEFAULT '[]', entity_references TEXT NOT NULL DEFAULT '[]',
        quarantine_reason TEXT, rabbit_uuid TEXT NOT NULL, operation_type TEXT NOT NULL,
        payload TEXT NOT NULL, base_version INTEGER NOT NULL, created_at TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'PENDING',
        last_error TEXT, server_snapshot TEXT
      );
      INSERT INTO rabbits (uuid,user_id,name,breed,sex,birth_date,status,genealogy_knowledge,
        created_at,updated_at,deleted_at,notes,weight)
        VALUES ('r',1,'Rabbit','rex','male','2024-01-01','active','FOUNDER','created','updated','deleted','original notes',2.5);
      INSERT INTO sync_operations (quarantine_reason,rabbit_uuid,operation_type,payload,
        base_version,created_at,status)
        VALUES ('legacy:unproven_owner','r','UPDATE','{"kept":true}',7,'original','FAILED');
      INSERT INTO sync_operations (owner_id,operation_uuid,dependencies,entity_references,
        rabbit_uuid,operation_type,payload,base_version,created_at,status,attempts,last_error)
        VALUES (1,'owned-op','["dep"]','["r"]','r','DELETE','{}',8,'later','PENDING',3,'previous error');
      PRAGMA user_version = 4;
    ''');
    legacy.dispose();

    for (var pass = 0; pass < 2; pass++) {
      final db = AppDatabase.file(file);
      try {
        final schema = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type IN ('table','index')",
            )
            .get();
        expect(
            schema.map((row) => row.read<String>('name')),
            containsAll([
              'local_parent_links',
              'local_reproductive_events',
              'r3_active_parent_role',
              'r3_events_owner_date',
            ]));
        final rabbit = await db.select(db.rabbits).getSingle();
        expect(rabbit.uuid, 'r');
        expect(rabbit.userId, 1);
        expect(rabbit.name, 'Rabbit');
        expect(rabbit.notes, 'original notes');
        expect(rabbit.weight, 2.5);
        expect(rabbit.status, 'active');
        expect(rabbit.genealogyKnowledge, 'FOUNDER');
        expect(rabbit.deletedAt, 'deleted');
        final operations = await db.select(db.syncOperations).get();
        expect(operations, hasLength(2));
        final queued = operations.singleWhere((row) => row.id == 1);
        expect(queued.ownerId, isNull);
        expect(queued.quarantineReason, 'legacy:unproven_owner');
        expect(queued.payload, '{"kept":true}');
        expect(queued.baseVersion, 7);
        expect(queued.status, 'FAILED');
        final owned = operations.singleWhere((row) => row.id == 2);
        expect(owned.ownerId, 1);
        expect(owned.operationUuid, 'owned-op');
        expect(owned.dependencies, '["dep"]');
        expect(owned.entityReferences, '["r"]');
        expect(owned.status, 'PENDING');
        expect(owned.attempts, 3);
        expect(owned.lastError, 'previous error');
      } finally {
        await db.close();
      }
    }
  });
}
