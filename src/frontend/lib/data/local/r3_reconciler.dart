import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/local_uuid.dart';
import 'app_database.dart';
import 'sync_evidence_store.dart';

class R3Reconciler {
  R3Reconciler(this.store);
  final SyncEvidenceStore store;
  AppDatabase get _db => store.db;
  int get _owner => store.ownerId;

  Future<void> applySnapshot(String id) => store.scoped(() async {
        final snapshot = await _db.customSelect(
          "SELECT * FROM r3_hydrations WHERE owner_id=? AND snapshot_uuid=? AND state='COMPLETE'",
          variables: [Variable(_owner), Variable(id)],
        ).getSingleOrNull();
        if (snapshot == null ||
            snapshot.readNullable<String>('applied_at') != null) return;
        final newer = await _db.customSelect("""
      SELECT 1 FROM r3_hydrations WHERE owner_id=? AND entity=? AND scope=?
        AND state='COMPLETE' AND applied_at IS NOT NULL AND revision > ? LIMIT 1
    """, variables: [
          Variable(_owner),
          Variable(snapshot.read<String>('entity')),
          Variable(snapshot.read<String>('scope')),
          Variable(snapshot.read<int>('revision')),
        ]).getSingleOrNull();
        if (newer != null) {
          await _db.customStatement(
              "UPDATE r3_hydrations SET state='STALE' WHERE owner_id=? AND snapshot_uuid=?",
              [_owner, id]);
          return;
        }
        final pages = await _db.customSelect("""
      SELECT items FROM r3_hydration_pages WHERE owner_id=? AND snapshot_uuid=? ORDER BY page
    """, variables: [Variable(_owner), Variable(id)]).get();
        final entity = snapshot.read<String>('entity');
        final rows = [
          for (final page in pages)
            ...(jsonDecode(page.read<String>('items')) as List)
                .cast<Map<String, dynamic>>(),
        ];
        // Retire old edges before projecting replacements of the same role.
        for (final deleted in [true, false]) {
          for (final row
              in rows.where((row) => (row['deleted_at'] != null) == deleted)) {
            await _reconcile(id, entity, row);
          }
        }
        await _db.customStatement(
            'UPDATE r3_hydrations SET applied_at=? WHERE owner_id=? AND snapshot_uuid=?',
            [DateTime.now().toUtc().toIso8601String(), _owner, id]);
      });

  Future<void> _reconcile(
      String snapshot, String entity, Map<String, dynamic> remote) async {
    final parent = entity == 'PARENT_LINK';
    final remoteId = remote[parent ? 'cycle_uuid' : 'uuid'] as String?;
    if (remoteId == null) return; // Unresolved history is retained in staging.
    final base = await _db.customSelect("""
      SELECT * FROM r3_remote_bases WHERE owner_id=? AND entity=? AND remote_id=?
    """, variables: [
      Variable(_owner),
      Variable(entity),
      Variable(remoteId)
    ]).getSingleOrNull();
    var mapping = await _db.customSelect("""
      SELECT local_uuid FROM sync_identity_mappings
      WHERE owner_id=? AND entity_type=? AND ${parent ? 'cycle_uuid' : 'remote_entity_uuid'}=?
    """, variables: [
      Variable(_owner),
      Variable(entity),
      Variable(remoteId)
    ]).getSingleOrNull();
    if (parent && mapping == null) {
      mapping = await _db.customSelect("""
        SELECT local_uuid FROM sync_identity_mappings
        WHERE owner_id=? AND entity_type='PARENT_LINK' AND cycle_uuid IS NULL
          AND child_uuid=? AND role=? AND creation_version=?
      """, variables: [
        Variable(_owner),
        Variable(remote['child_uuid'] as String),
        Variable(remote['role'] as String),
        Variable(remote['creation_version'] as int)
      ]).getSingleOrNull();
    }
    final localId =
        base?.read<String>('local_uuid') ?? mapping?.read<String>('local_uuid');
    final version = remote['version'] as int;
    var baseline = base == null
        ? null
        : jsonDecode(base.read<String>('payload')) as Map<String, dynamic>;
    if (base != null && base.read<int>('remote_version') > version) return;
    final newerObservation = await _db.customSelect(r'''
      SELECT 1 FROM r3_hydrations h JOIN r3_hydration_pages p
        ON h.owner_id=p.owner_id AND h.snapshot_uuid=p.snapshot_uuid
      JOIN json_each(p.items) item
      WHERE h.owner_id=? AND h.entity=? AND h.state IN ('COMPLETE','STALE')
        AND h.applied_at IS NOT NULL AND json_extract(item.value, ?)=?
        AND json_extract(item.value, '$.version')>? LIMIT 1
    ''', variables: [
      Variable(_owner),
      Variable(entity),
      Variable(parent ? r'$.cycle_uuid' : r'$.uuid'),
      Variable(remoteId),
      Variable(version),
    ]).getSingleOrNull();
    if (newerObservation != null) return;
    final local = localId == null ? null : await localState(entity, localId);
    final receipt = localId == null
        ? null
        : await _db.customSelect("""
      SELECT r.remote_version AS version, r.response_json
      FROM sync_operation_results r JOIN sync_operations o
        ON r.owner_id=o.owner_id AND r.operation_uuid=o.operation_uuid
      WHERE o.owner_id=? AND o.entity_type=? AND o.rabbit_uuid=? AND o.status='COMPLETED'
      ORDER BY r.remote_version DESC LIMIT 1
    """, variables: [
            Variable(_owner),
            Variable(entity),
            Variable(localId)
          ]).getSingleOrNull();
    final receiptVersion = receipt?.readNullable<int>('version');
    if (receiptVersion != null && receiptVersion > version) return;
    if (receiptVersion != null &&
        (base == null || receiptVersion > base.read<int>('remote_version'))) {
      final body = receipt!.readNullable<String>('response_json');
      if (body != null) baseline = jsonDecode(body) as Map<String, dynamic>;
    }
    final pending =
        localId == null ? null : await pendingOperation(entity, localId);
    final sameRemote = baseline != null &&
        fingerprint(entity, baseline) == fingerprint(entity, remote);
    final sameLocal = local != null &&
        fingerprint(entity, local) == fingerprint(entity, remote);
    if (base != null &&
        base.read<int>('remote_version') == version &&
        !sameRemote) {
      await conflict(snapshot, entity, remoteId, localId, baseline, local,
          remote, pending, 'same_version_changed');
      return;
    }
    if (pending?.status == 'CONFLICT') {
      await conflict(snapshot, entity, remoteId, localId, baseline, local,
          remote, pending, 'publication_conflict');
      return;
    }
    if (pending != null ||
        (local != null &&
            !sameLocal &&
            (baseline == null ||
                fingerprint(entity, baseline) != fingerprint(entity, local)))) {
      if (!sameRemote && !sameLocal) {
        await conflict(snapshot, entity, remoteId, localId, baseline, local,
            remote, pending, 'concurrent_change');
      }
      return;
    }
    final id = localId ?? newLocalUuid();
    if (!await canProject(entity, id, remote)) {
      await conflict(snapshot, entity, remoteId, localId, baseline, local,
          remote, pending, 'invalid_or_colliding_projection');
      return;
    }
    if (!sameLocal) await project(entity, id, remote);
    await saveBase(snapshot, entity, remoteId, id, remote);
  }

  Future<Map<String, dynamic>?> localState(String entity, String id) async {
    final table = entity == 'PARENT_LINK'
        ? 'local_parent_links'
        : 'local_reproductive_events';
    final row = await _db.customSelect(
      'SELECT * FROM $table WHERE owner_id=? AND uuid=?',
      variables: [Variable(_owner), Variable(id)],
    ).getSingleOrNull();
    return row?.data;
  }

  Future<LocalSyncOperation?> pendingOperation(String entity, String id) =>
      (_db.select(_db.syncOperations)
            ..where((t) =>
                t.ownerId.equals(_owner) &
                t.entityType.equals(entity) &
                t.rabbitUuid.equals(id) &
                t.status.isNotIn(['COMPLETED', 'SUPERSEDED']))
            ..orderBy([(t) => OrderingTerm.asc(t.id)])
            ..limit(1))
          .getSingleOrNull();

  Future<bool> canProject(
      String entity, String id, Map<String, dynamic> row) async {
    if (entity != 'PARENT_LINK' || row['deleted_at'] != null) return true;
    final child = row['child_uuid'];
    final parent = row['parent_uuid'];
    final role = row['role'];
    final invalid = await _db.customSelect("""
      WITH RECURSIVE ancestors(uuid) AS (
        SELECT ? UNION SELECT link.parent_uuid
        FROM local_parent_links link JOIN ancestors a ON a.uuid=link.child_uuid
        WHERE link.owner_id=? AND link.deleted_at IS NULL AND link.uuid<>?
      )
      SELECT 1 WHERE EXISTS (SELECT 1 FROM ancestors WHERE uuid=?)
        OR EXISTS (SELECT 1 FROM local_parent_links WHERE owner_id=?
          AND child_uuid=? AND deleted_at IS NULL AND uuid<>?
          AND (role=? OR parent_uuid=?))
        OR EXISTS (SELECT 1 FROM rabbits WHERE user_id=? AND quarantine_reason IS NULL
          AND ((uuid=? AND genealogy_knowledge='FOUNDER') OR (uuid=? AND sex<>?)))
    """, variables: [
      Variable(parent as String),
      Variable(_owner),
      Variable(id),
      Variable(child as String),
      Variable(_owner),
      Variable(child),
      Variable(id),
      Variable(role as String),
      Variable(parent),
      Variable(_owner),
      Variable(child),
      Variable(parent),
      Variable(role == 'FATHER' ? 'male' : 'female'),
    ]).getSingleOrNull();
    return invalid == null;
  }

  Future<void> project(
      String entity, String id, Map<String, dynamic> row) async {
    final existing = await localState(entity, id);
    var localVersion = existing == null ? 1 : (existing['version'] as int) + 1;
    if (entity == 'PARENT_LINK') {
      final latest = await _db.customSelect('''
        SELECT MAX(version) AS version FROM local_parent_links
        WHERE owner_id=? AND child_uuid=? AND role=?
      ''', variables: [
        Variable(_owner),
        Variable(row['child_uuid'] as String),
        Variable(row['role'] as String),
      ]).getSingle();
      localVersion = (latest.readNullable<int>('version') ?? 0) + 1;
      await _db
          .into(_db.localParentLinks)
          .insertOnConflictUpdate(StoredParentLink(
            uuid: id,
            ownerId: _owner,
            childUuid: row['child_uuid'],
            parentUuid: row['parent_uuid'],
            role: row['role'],
            version: localVersion,
            createdAt: row['created_at'],
            updatedAt: row['updated_at'],
            deletedAt: row['deleted_at'],
          ));
    } else {
      await _db
          .into(_db.localReproductiveEvents)
          .insertOnConflictUpdate(StoredReproductiveEvent(
            uuid: id,
            ownerId: _owner,
            maleUuid: row['male_uuid'],
            femaleUuid: row['female_uuid'],
            matingDate: row['mating_date'],
            notes: row['notes'],
            version: localVersion,
            createdAt: row['created_at'],
            updatedAt: row['updated_at'],
            deletedAt: row['deleted_at'],
          ));
    }
  }

  Future<void> saveBase(String snapshot, String entity, String remoteId,
      String id, Map<String, dynamic> row) async {
    final parent = entity == 'PARENT_LINK';
    await _db.customStatement("""
      INSERT INTO sync_identity_mappings
        (owner_id,entity_type,local_uuid,remote_entity_uuid,child_uuid,role,creation_version,cycle_uuid)
      VALUES (?,?,?,?,?,?,?,?)
      ON CONFLICT(owner_id,entity_type,local_uuid) DO UPDATE SET cycle_uuid=excluded.cycle_uuid
      WHERE sync_identity_mappings.cycle_uuid IS NULL
    """, [
      _owner,
      entity,
      id,
      parent ? null : remoteId,
      row['child_uuid'],
      row['role'],
      row['creation_version'],
      parent ? remoteId : null
    ]);
    await _db.customStatement("""
    INSERT INTO r3_remote_bases VALUES (?,?,?,?,?,?,?)
    ON CONFLICT(owner_id,entity,remote_id) DO UPDATE SET
      remote_version=excluded.remote_version,payload=excluded.payload,snapshot_uuid=excluded.snapshot_uuid
    """, [
      _owner,
      entity,
      remoteId,
      id,
      row['version'],
      jsonEncode(row),
      snapshot
    ]);
  }

  Future<void> conflict(
      String snapshot,
      String entity,
      String remoteId,
      String? id,
      Map<String, dynamic>? base,
      Map<String, dynamic>? local,
      Map<String, dynamic> remote,
      LocalSyncOperation? pending,
      String reason) async {
    await _db.customStatement("""
      INSERT OR IGNORE INTO r3_conflicts
        (owner_id,uuid,entity,remote_id,local_uuid,snapshot_uuid,base,local,remote,
         local_version,remote_version,operation_uuid,reason,detected_at,state)
      SELECT ?,?,?,?,?,?,?,?,?,?,?,?,?,?,'OPEN'
      WHERE NOT EXISTS (
        SELECT 1 FROM r3_conflicts WHERE owner_id=? AND entity=? AND remote_id=?
          AND local IS ? AND remote=? AND operation_uuid IS ? AND state='OPEN'
      )
    """, [
      _owner,
      newLocalUuid(),
      entity,
      remoteId,
      id,
      snapshot,
      base == null ? null : jsonEncode(base),
      local == null ? null : jsonEncode(local),
      jsonEncode(remote),
      local?['version'],
      remote['version'],
      pending?.operationUuid,
      reason,
      DateTime.now().toUtc().toIso8601String(),
      _owner,
      entity,
      remoteId,
      local == null ? null : jsonEncode(local),
      jsonEncode(remote),
      pending?.operationUuid,
    ]);
    await _db.customStatement("""
      UPDATE r3_conflicts SET state='BLOCKED'
      WHERE owner_id=? AND entity=? AND remote_id=? AND snapshot_uuid<>?
        AND remote_version < ? AND state='OPEN'
    """, [_owner, entity, remoteId, snapshot, remote['version']]);
    // An in-flight operation retains its claim and must replay before resolution.
    if (pending != null && pending.status == 'PENDING') {
      await (_db.update(_db.syncOperations)
            ..where((t) => t.ownerId.equals(_owner) & t.id.equals(pending.id)))
          .write(const SyncOperationsCompanion(status: Value('CONFLICT')));
    }
  }

  static String fingerprint(String entity, Map<String, dynamic> row) =>
      jsonEncode([
        if (entity == 'PARENT_LINK') ...[
          row['child_uuid'],
          row['role'],
          row['parent_uuid']
        ] else ...[
          row['male_uuid'],
          row['female_uuid'],
          row['mating_date'],
          row['notes']
        ],
        row['deleted_at'] != null,
      ]);
}
