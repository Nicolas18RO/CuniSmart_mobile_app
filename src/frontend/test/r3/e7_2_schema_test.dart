import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v6 upgrade preserves an active frozen attempt', () async {
    final dir = await Directory.systemTemp.createTemp('cunismart_e72_v6_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/test.sqlite');
    final initial = AppDatabase.file(file);
    await initial.customStatement('''
      INSERT INTO sync_frozen_commands
        (owner_id,operation_uuid,canonical_command,request_hash,
         attempt_uuid,session_generation,process_uuid)
      VALUES (1,'op','{}',?,'attempt',2,'process')
    ''', [List.filled(64, 'a').join()]);
    await initial.close();
    final fixture = sqlite3.open(file.path);
    fixture.execute('''
      ALTER TABLE sync_frozen_commands DROP COLUMN derived_from_uuid;
      ALTER TABLE sync_frozen_commands DROP COLUMN retry_at;
      DROP INDEX r3_mapping_cycle;
      ALTER TABLE sync_identity_mappings DROP COLUMN cycle_uuid;
      DROP TABLE r3_hydration_pages;
      DROP TABLE r3_hydrations;
      DROP TABLE r3_remote_bases;
      DROP TABLE r3_conflicts;
      PRAGMA user_version = 6;
    ''');
    fixture.dispose();
    final upgraded = AppDatabase.file(file);
    try {
      final row = await upgraded
          .customSelect('SELECT * FROM sync_frozen_commands')
          .getSingle();
      expect(row.read<String>('canonical_command'), '{}');
      expect(row.read<String>('attempt_uuid'), 'attempt');
      expect(row.read<int>('session_generation'), 2);
      expect(row.readNullable<String>('derived_from_uuid'), isNull);
    } finally {
      await upgraded.close();
    }
  });

  for (final version in [1, 2, 3]) {
    test('v$version upgrade preserves legacy data and quarantines intent',
        () async {
      final dir = await Directory.systemTemp.createTemp('cunismart_e72_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/test.sqlite');
      final fixture = sqlite3.open(file.path);
      fixture.execute("""
        CREATE TABLE rabbits (
          uuid TEXT NOT NULL PRIMARY KEY, server_id INTEGER,
          user_id INTEGER NOT NULL, name TEXT NOT NULL, breed TEXT NOT NULL,
          sex TEXT NOT NULL, birth_date TEXT NOT NULL, weight REAL,
          status TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
          version INTEGER NOT NULL DEFAULT 1, deleted_at TEXT,
          sync_status TEXT NOT NULL DEFAULT 'SYNCED'
          ${version >= 3 ? ", genealogy_knowledge TEXT NOT NULL DEFAULT 'UNKNOWN'" : ""}
        );
        INSERT INTO rabbits
          (uuid, user_id, name, breed, sex, birth_date, status, created_at, updated_at)
        VALUES ('r', 1, 'Rabbit', 'rex', 'male', '2024-01-01', 'active', 'then', 'then');
        PRAGMA user_version = $version;
      """);
      if (version >= 2) {
        fixture.execute("""
          CREATE TABLE sync_operations (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            rabbit_uuid TEXT NOT NULL, operation_type TEXT NOT NULL,
            payload TEXT NOT NULL, base_version INTEGER NOT NULL,
            created_at TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'PENDING', last_error TEXT,
            server_snapshot TEXT
          );
          INSERT INTO sync_operations
            (rabbit_uuid, operation_type, payload, base_version, created_at)
          VALUES ('r', 'UPDATE', '{"kept":true}', 1, 'then');
        """);
      }
      fixture.dispose();
      final db = AppDatabase.file(file);
      try {
        expect((await db.select(db.rabbits).getSingle()).uuid, 'r');
        final rows = await db.select(db.syncOperations).get();
        if (version == 1) {
          expect(rows, isEmpty);
        } else {
          expect(rows.single.payload, '{"kept":true}');
          expect(rows.single.ownerId, isNull);
          expect(rows.single.operationUuid, isNull);
          expect(rows.single.quarantineReason, 'legacy:unproven_owner');
        }
        final schema = await db.customSelect('PRAGMA user_version').getSingle();
        expect(schema.read<int>('user_version'), 10);
      } finally {
        await db.close();
      }
    });
  }

  test('v5 upgrade preserves queue evidence across two opens', () async {
    final dir = await Directory.systemTemp.createTemp('cunismart_e72_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/test.sqlite');
    final original = AppDatabase.file(file);
    await original.customStatement('''
      INSERT INTO sync_operations
        (rabbit_uuid, operation_type, payload, base_version, created_at,
         dependencies, entity_references, quarantine_reason, server_snapshot)
      VALUES ('rabbit', 'UPDATE', '{}', 3, 'then', '["dep"]', '["rabbit"]',
              'legacy:unproven_owner', '{"version":4}')
    ''');
    await original.close();

    // Reproduce a v5 file by removing only the v6 objects from this test fixture.
    final fixture = sqlite3.open(file.path);
    fixture.execute('''
      DROP TABLE sync_frozen_commands;
      DROP TABLE sync_operation_results;
      DROP TABLE sync_identity_mappings;
      DROP TABLE sync_create_cancellations;
      DROP TABLE sync_rabbit_preimages;
      DROP TABLE r3_hydration_pages;
      DROP TABLE r3_hydrations;
      DROP TABLE r3_remote_bases;
      DROP TABLE r3_conflicts;
      PRAGMA user_version = 5;
    ''');
    fixture.dispose();

    for (var pass = 0; pass < 2; pass++) {
      final db = AppDatabase.file(file);
      try {
        final op = await db.select(db.syncOperations).getSingle();
        expect(op.ownerId, isNull);
        expect(op.operationUuid, isNull);
        expect(op.quarantineReason, 'legacy:unproven_owner');
        expect(op.dependencies, '["dep"]');
        expect(op.entityReferences, '["rabbit"]');
        expect(op.serverSnapshot, '{"version":4}');
        final version =
            await db.customSelect('PRAGMA user_version').getSingle();
        expect(version.read<int>('user_version'), 10);
        if (pass == 0) {
          Future<void> insert(int owner) => db.customStatement('''
            INSERT INTO sync_identity_mappings
              (owner_id, entity_type, local_uuid, remote_entity_uuid)
            VALUES (?, 'REPRODUCTIVE_EVENT', 'local', 'remote')
          ''', [owner]);
          await insert(1);
          await insert(2);
          await expectLater(insert(1), throwsA(isA<SqliteException>()));
          await expectLater(db.transaction(() async {
            await insert(3);
            throw StateError('abort');
          }), throwsStateError);
        }
        final rows = await db
            .customSelect(
                'SELECT owner_id FROM sync_identity_mappings ORDER BY owner_id')
            .get();
        expect(rows.map((row) => row.read<int>('owner_id')), [1, 2]);
      } finally {
        await db.close();
      }
    }
  });
}
