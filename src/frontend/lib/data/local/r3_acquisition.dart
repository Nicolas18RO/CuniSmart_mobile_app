import 'dart:convert';

import 'package:drift/drift.dart';

import 'app_database.dart';
import 'sync_command.dart';
import 'sync_dependency_evaluator.dart';
import 'sync_evidence_store.dart';

/// Resolves and claims one operation under the same transaction as the DAG read.
class R3Acquisition {
  R3Acquisition(this.store);

  final SyncEvidenceStore store;

  Future<FrozenAttempt?> next(Set<String> visited) => store.scoped(() async {
        final db = store.db;
        final plan = await SyncDependencyEvaluator(store)
            .evaluate(includeRecovering: true);
        for (final uuid in plan.eligible) {
          if (!visited.add(uuid)) continue;
          final op = (await store.operation(uuid))!;
          if (op.status == 'SYNCING') {
            final recovery =
                await store.claim(uuid, recovering: true, publication: true);
            if (recovery != null) return recovery;
            continue;
          }
          final command = await _command(op);
          if (command == null) {
            await (db.update(db.syncOperations)
                  ..where((t) => t.id.equals(op.id)))
                .write(const SyncOperationsCompanion(
                    lastError: Value('r3_remote_evidence_missing')));
            continue;
          }
          final frozen = await store.frozenCommand(uuid);
          if (frozen != null && frozen != command) {
            await (db.update(db.syncOperations)
                  ..where((t) => t.id.equals(op.id)))
                .write(const SyncOperationsCompanion(
                    lastError: Value('r3_frozen_command_mismatch')));
            continue;
          }
          await store.freeze(uuid, command, syncRequestHash(command));
          final attempt = await store.claim(uuid, publication: true);
          if (attempt != null) return attempt;
        }
        return null;
      });

  Future<String?> _command(LocalSyncOperation op) async {
    final db = store.db;
    final parent = op.entityType == 'PARENT_LINK';
    final create = op.operationType == 'CREATE';
    final delete = op.operationType == 'DELETE';
    final source = jsonDecode(op.payload) as Map<String, dynamic>;
    String? remoteUuid;
    int? version;
    if (!create) {
      final mapping = await db.customSelect('''
        SELECT * FROM sync_identity_mappings
        WHERE owner_id = ? AND entity_type = ? AND local_uuid = ?
      ''', variables: [
        Variable(store.ownerId),
        Variable(op.entityType),
        Variable(op.rabbitUuid)
      ]).getSingleOrNull();
      if (mapping == null) return null;
      if (parent &&
          (mapping.readNullable<String>('cycle_uuid') == null ||
              mapping.readNullable<String>('child_uuid') !=
                  source['child_uuid'] ||
              mapping.readNullable<String>('role') != source['role'])) {
        return null;
      }
      remoteUuid = mapping.readNullable<String>('remote_entity_uuid');
      final evidence = await db.customSelect('''
        SELECT r.remote_version, r.remote_entity_uuid, o.operation_type
        FROM sync_operation_results r JOIN sync_operations o
          ON r.owner_id = o.owner_id AND r.operation_uuid = o.operation_uuid
        WHERE r.owner_id = ? AND o.entity_type = ? AND o.rabbit_uuid = ?
          AND o.status = 'COMPLETED' AND o.quarantine_reason IS NULL
        ORDER BY r.remote_version DESC, o.id DESC LIMIT 1
      ''', variables: [
        Variable(store.ownerId),
        Variable(op.entityType),
        Variable(op.rabbitUuid)
      ]).getSingleOrNull();
      version = evidence?.readNullable<int>('remote_version');
      final base = await db.customSelect('''
        SELECT remote_version, payload FROM r3_remote_bases
        WHERE owner_id=? AND entity=? AND local_uuid=? AND remote_id=?
      ''', variables: [
        Variable(store.ownerId),
        Variable(op.entityType),
        Variable(op.rabbitUuid),
        Variable(
            parent ? mapping.readNullable<String>('cycle_uuid') : remoteUuid)
      ]).getSingleOrNull();
      if (base != null &&
          (version == null || base.read<int>('remote_version') > version)) {
        if ((jsonDecode(base.read<String>('payload')) as Map)['deleted_at'] !=
            null) {
          return null;
        }
        version = base.read<int>('remote_version');
      } else {
        if (version == null ||
            evidence?.read<String>('operation_type') == 'DELETE' ||
            (!parent &&
                (remoteUuid == null ||
                    remoteUuid !=
                        evidence
                            ?.readNullable<String>('remote_entity_uuid')))) {
          return null;
        }
      }
    }
    final route = parent
        ? "/api/rabbits/${source['child_uuid']}/parents/${source['role']}/"
        : create
            ? '/api/reproductive-events/'
            : '/api/reproductive-events/$remoteUuid/';
    final payload = <String, Object?>{
      if (!delete && parent) 'parent_uuid': source['parent_uuid'],
      if (!parent && create) ...{
        'male_uuid': source['male_uuid'],
        'female_uuid': source['female_uuid'],
      },
      if (!parent && !delete) ...{
        if (source.containsKey('mating_date'))
          'mating_date': source['mating_date'],
        if (source.containsKey('notes')) 'notes': source['notes'],
      },
    };
    return canonicalSyncCommand(
        entityType: op.entityType,
        action: op.operationType,
        destination: route,
        payload: payload,
        expectedVersion: version);
  }
}
