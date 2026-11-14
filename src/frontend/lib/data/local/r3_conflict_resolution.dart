import 'dart:convert';

import 'package:drift/drift.dart';

import 'app_database.dart';
import 'r3_reconciler.dart';
import 'sync_evidence_store.dart';

enum R3Resolution { remote, local, manual }

class R3ConflictResolution {
  R3ConflictResolution(this.store);

  final SyncEvidenceStore store;

  Future<List<QueryRow>> open() => store.scoped(() => store.db.customSelect(
        "SELECT * FROM r3_conflicts WHERE owner_id=? AND state IN ('OPEN','BLOCKED') ORDER BY detected_at",
        variables: [Variable(store.ownerId)],
      ).get());

  Future<bool> resolve(String id, R3Resolution decision,
          {String? adjustedNotes, bool requireFreshObservation = false}) =>
      store.scoped(() async {
        final db = store.db;
        final conflict = await db.customSelect("""
      SELECT c.*, h.revision FROM r3_conflicts c JOIN r3_hydrations h
        ON h.owner_id=c.owner_id AND h.snapshot_uuid=c.snapshot_uuid
      WHERE c.owner_id=? AND c.uuid=? AND c.state='OPEN'
    """, variables: [Variable(store.ownerId), Variable(id)]).getSingleOrNull();
        if (conflict == null) return false;
        final entity = conflict.read<String>('entity');
        final localId = conflict.readNullable<String>('local_uuid');
        final remoteId = conflict.read<String>('remote_id');
        final originalId = conflict.readNullable<String>('operation_uuid');
        final version = conflict.read<int>('remote_version');
        final remote =
            jsonDecode(conflict.read<String>('remote')) as Map<String, dynamic>;
        final local = conflict.readNullable<String>('local');
        final reconciler = R3Reconciler(store);
        final original =
            originalId == null ? null : await store.operation(originalId);
        final current = localId == null
            ? null
            : await reconciler.localState(entity, localId);
        final newer = await db.customSelect(r"""
      SELECT 1 FROM r3_hydrations h JOIN r3_hydration_pages p
        ON h.owner_id=p.owner_id AND h.snapshot_uuid=p.snapshot_uuid
      JOIN json_each(p.items) item
      WHERE h.owner_id=? AND h.entity=? AND h.state='COMPLETE' AND h.revision>?
        AND json_extract(item.value, ?) = ?
        AND (json_extract(item.value, '$.version') > ? OR
             (json_extract(item.value, '$.version') = ? AND json(item.value) <> json(?)))
      LIMIT 1
    """, variables: [
          Variable(store.ownerId),
          Variable(entity),
          Variable(conflict.read<int>('revision')),
          Variable(entity == 'PARENT_LINK' ? r'$.cycle_uuid' : r'$.uuid'),
          Variable(remoteId),
          Variable(version),
          Variable(version),
          Variable(conflict.read<String>('remote')),
        ]).getSingleOrNull();
        final advancedReceipt = localId == null
            ? null
            : await db.customSelect("""
      SELECT 1 FROM sync_operation_results r JOIN sync_operations o
        ON r.owner_id=o.owner_id AND r.operation_uuid=o.operation_uuid
      WHERE o.owner_id=? AND o.entity_type=? AND o.rabbit_uuid=? AND r.remote_version>?
      LIMIT 1
    """, variables: [
                Variable(store.ownerId),
                Variable(entity),
                Variable(localId),
                Variable(version)
              ]).getSingleOrNull();
        final fresh = !requireFreshObservation ||
            await db.customSelect(r'''
          SELECT 1 FROM r3_hydrations h JOIN r3_hydration_pages p
            ON h.owner_id=p.owner_id AND h.snapshot_uuid=p.snapshot_uuid
          JOIN json_each(p.items) item
          WHERE h.owner_id=? AND h.entity=? AND h.state='COMPLETE' AND h.revision>?
            AND json_extract(item.value, ?)=?
            AND json_extract(item.value, '$.version')=? LIMIT 1
        ''', variables: [
                  Variable(store.ownerId),
                  Variable(entity),
                  Variable(conflict.read<int>('revision')),
                  Variable(
                      entity == 'PARENT_LINK' ? r'$.cycle_uuid' : r'$.uuid'),
                  Variable(remoteId),
                  Variable(version),
                ]).getSingleOrNull() !=
                null;
        if (!fresh ||
            newer != null ||
            advancedReceipt != null ||
            localId == null ||
            current == null ||
            jsonEncode(current) != local ||
            (originalId != null && original?.status != 'CONFLICT')) {
          await db.customStatement(
              "UPDATE r3_conflicts SET state='BLOCKED' WHERE owner_id=? AND uuid=?",
              [store.ownerId, id]);
          return false;
        }
        final intents = await (db.select(db.syncOperations)
              ..where((t) =>
                  t.ownerId.equals(store.ownerId) &
                  t.entityType.equals(entity) &
                  t.rabbitUuid.equals(localId) &
                  t.status.isNotIn(['COMPLETED', 'SUPERSEDED'])))
            .get();
        // Other edits require separate review. An uncertain claim must replay first.
        if (intents.any((op) =>
            op.operationUuid != originalId || op.quarantineReason != null)) {
          return false;
        }

        String? successor;
        if (decision == R3Resolution.remote) {
          if (!await reconciler.canProject(entity, localId, remote)) {
            return false;
          }
          await reconciler.project(entity, localId, remote);
        } else {
          if (original == null ||
              original.operationType == 'CREATE' ||
              remote['deleted_at'] != null) {
            return false;
          }
          final parent = entity == 'PARENT_LINK';
          final deleting = original.operationType == 'DELETE';
          if (decision == R3Resolution.manual &&
              (deleting ||
                  adjustedNotes == null ||
                  adjustedNotes.length > 4000)) {
            return false;
          }
          final resolved = {...current};
          if (decision == R3Resolution.manual) {
            if (parent) {
              final rabbit = await db.customSelect(
                'SELECT 1 FROM rabbits WHERE user_id=? AND uuid=? AND deleted_at IS NULL AND quarantine_reason IS NULL',
                variables: [Variable(store.ownerId), Variable(adjustedNotes!)],
              ).getSingleOrNull();
              if (rabbit == null) return false;
              resolved['parent_uuid'] = adjustedNotes;
            } else {
              resolved['notes'] = adjustedNotes;
            }
          }
          if (!await reconciler.canProject(entity, localId, resolved)) {
            return false;
          }
          final destination = parent
              ? "/api/rabbits/${remote['child_uuid']}/parents/${remote['role']}/"
              : '/api/reproductive-events/$remoteId/';
          successor = await store.derive(original.operationUuid!,
              destination: destination,
              expectedVersion: version,
              fromReconciliation: true,
              payload: deleting
                  ? {}
                  : parent
                      ? {'parent_uuid': resolved['parent_uuid']}
                      : {
                          'mating_date': resolved['mating_date'],
                          'notes': resolved['notes']
                        });
          if (decision == R3Resolution.manual) {
            await reconciler.project(entity, localId, resolved);
          }
        }
        await reconciler.saveBase(conflict.read<String>('snapshot_uuid'),
            entity, remoteId, localId, remote);
        if (original != null) {
          // SUPERSEDED is audit evidence, never a transport completion.
          await (db.update(db.syncOperations)
                ..where((t) =>
                    t.ownerId.equals(store.ownerId) & t.id.equals(original.id)))
              .write(
                  const SyncOperationsCompanion(status: Value('SUPERSEDED')));
        }
        await db.customStatement("""
      UPDATE r3_conflicts SET state=?,decision=?,resolved_at=?,successor_uuid=?
      WHERE owner_id=? AND uuid=?
    """, [
          'RESOLVED_${decision.name.toUpperCase()}',
          decision.name,
          DateTime.now().toUtc().toIso8601String(),
          successor,
          store.ownerId,
          id
        ]);
        return true;
      });
}
