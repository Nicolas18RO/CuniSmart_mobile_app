import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'rabbits_table.dart';
import 'r3_tables.dart';
import 'sync_operations_table.dart';

part 'app_database.g.dart';
part 'sync_evidence_schema.dart';
part 'r3_hydration_schema.dart';

@DriftDatabase(tables: [
  Rabbits,
  SyncOperations,
  LocalParentLinks,
  LocalReproductiveEvents
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  factory AppDatabase.file(File file) => AppDatabase(NativeDatabase(file));

  factory AppDatabase.fromDocuments() {
    return AppDatabase(LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'cunismart.sqlite'));
      return NativeDatabase.createInBackground(file);
    }));
  }

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createOwnerIndexes();
          await _createR3Indexes();
          await _createSyncEvidenceSchema();
          await _addSyncLineage();
          await _addSyncRetry();
          await _createR3HydrationSchema();
          await _createR3ReconciliationSchema();
        },
        onUpgrade: (m, from, to) async {
          await transaction(() async {
            if (from < 2) {
              await m.createTable(syncOperations);
            }
            if (from < 3) {
              await m.addColumn(rabbits, rabbits.genealogyKnowledge);
            }
            if (from < 4) {
              await m.addColumn(rabbits, rabbits.quarantineReason);
              if (from >= 2) {
                await m.addColumn(syncOperations, syncOperations.ownerId);
                await m.addColumn(syncOperations, syncOperations.operationUuid);
                await m.addColumn(syncOperations, syncOperations.entityType);
                await m.addColumn(syncOperations, syncOperations.dependencies);
                await m.addColumn(
                    syncOperations, syncOperations.entityReferences);
                await m.addColumn(
                    syncOperations, syncOperations.quarantineReason);
              }
              await customStatement(
                "UPDATE rabbits SET quarantine_reason = 'legacy:unknown_owner' WHERE user_id <= 0",
              );
              await customStatement(
                "UPDATE rabbits SET quarantine_reason = 'legacy:unproven_mutation' "
                "WHERE user_id > 0 AND sync_status <> 'SYNCED'",
              );
              await customStatement(
                "UPDATE sync_operations SET quarantine_reason = 'legacy:unproven_owner'",
              );
              await _createOwnerIndexes();
            }
            if (from < 5) {
              await m.createTable(localParentLinks);
              await m.createTable(localReproductiveEvents);
              await _createR3Indexes();
            }
            if (from < 6) {
              await _createSyncEvidenceSchema();
            }
            if (from < 7) {
              await _addSyncLineage();
            }
            if (from < 8) {
              await _addSyncRetry();
            }
            if (from < 9) {
              await _createR3HydrationSchema();
            }
            if (from < 10) {
              await _createR3ReconciliationSchema();
            }
          });
        },
      );

  Future<void> _createR3HydrationSchema() async {
    for (final statement in _r3HydrationSchema) {
      await customStatement(statement);
    }
  }

  Future<void> _createR3ReconciliationSchema() async {
    for (final statement in _r3ReconciliationSchema) {
      await customStatement(statement);
    }
  }

  Future<void> _addSyncLineage() => customStatement(
        'ALTER TABLE sync_frozen_commands ADD COLUMN derived_from_uuid TEXT',
      );

  Future<void> _addSyncRetry() => customStatement(
        'ALTER TABLE sync_frozen_commands ADD COLUMN retry_at INTEGER',
      );

  Future<void> _createSyncEvidenceSchema() async {
    for (final statement in _e72Schema) {
      await customStatement(statement);
    }
  }

  Future<void> _createR3Indexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX r3_active_parent_role '
      'ON local_parent_links(owner_id, child_uuid, role) WHERE deleted_at IS NULL',
    );
    await customStatement(
      'CREATE INDEX r3_parent_history ON local_parent_links(owner_id, child_uuid, role, version)',
    );
    await customStatement(
      'CREATE INDEX r3_events_owner_date ON local_reproductive_events(owner_id, mating_date)',
    );
  }

  Future<void> _createOwnerIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS rabbits_owner ON rabbits(user_id, deleted_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS sync_operations_owner ON sync_operations(owner_id, status, id)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS sync_operations_uuid ON sync_operations(operation_uuid)',
    );
  }
}
