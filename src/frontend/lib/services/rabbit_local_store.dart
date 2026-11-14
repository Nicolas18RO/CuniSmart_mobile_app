import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/errors/api_exception.dart';
import '../data/local/app_database.dart';
import '../data/local/sync_evidence_store.dart';
import '../models/local_uuid.dart';
import '../models/rabbit.dart';
import '../models/sync_operation.dart';
import '../models/sync_status.dart';

/// Drift access for rabbits and the sync queue. Mapping lives here, not in widgets.
class RabbitLocalStore {
  RabbitLocalStore(this._db, {this.ownerId, bool Function()? isCurrent})
      : _isCurrent = isCurrent;

  RabbitLocalStore.accountScopes(this._db)
      : ownerId = null,
        _isCurrent = _noAccount;

  static bool _noAccount() => false;

  RabbitLocalStore forOwner(int owner, bool Function() isCurrent) =>
      RabbitLocalStore(_db, ownerId: owner, isCurrent: isCurrent);

  final int? ownerId;
  final bool Function()? _isCurrent;

  void checkSession() {
    if (_isCurrent?.call() == false) {
      throw ApiException('La sesión cambió', code: 'session_changed');
    }
  }

  Expression<bool> _ownedRabbit($RabbitsTable table) => ownerId == null
      ? const Constant(true)
      : table.userId.equals(ownerId!) & table.quarantineReason.isNull();

  Expression<bool> _ownedOperation($SyncOperationsTable table) {
    final rabbit =
        table.entityType.equals('RABBIT') & table.quarantineReason.isNull();
    return ownerId == null ? rabbit : rabbit & table.ownerId.equals(ownerId!);
  }

  Future<T> transaction<T>(Future<T> Function() action) =>
      _db.transaction(() async {
        checkSession();
        final result = await action();
        checkSession();
        return result;
      });

  final AppDatabase _db;

  SyncEvidenceStore syncEvidence(
          int owner, int generation, bool Function() current) =>
      SyncEvidenceStore(_db,
          ownerId: owner, generation: generation, isCurrent: current);

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  Future<List<Rabbit>> readActive() async {
    checkSession();
    final rows = await (_db.select(_db.rabbits)
          ..where((t) => _ownedRabbit(t) & t.deletedAt.isNull()))
        .get();
    return rows.map(_toRabbit).toList();
  }

  Future<Rabbit?> readByUuid(String uuid) async {
    checkSession();
    final row = await (_db.select(_db.rabbits)
          ..where((t) => _ownedRabbit(t) & t.uuid.equals(uuid)))
        .getSingleOrNull();
    return row == null ? null : _toRabbit(row);
  }

  Future<List<Rabbit>> readByUuids(Set<String> uuids) async {
    checkSession();
    final ids = uuids.toList(growable: false);
    final result = <Rabbit>[];
    for (var offset = 0; offset < ids.length; offset += 500) {
      final rows = await (_db.select(_db.rabbits)
            ..where((t) =>
                _ownedRabbit(t) & t.uuid.isIn(ids.skip(offset).take(500))))
          .get();
      checkSession();
      result.addAll(rows.map(_toRabbit));
    }
    return result;
  }

  Future<void> upsert(Rabbit rabbit) async {
    checkSession();
    final owner = ownerId;
    if (owner != null) {
      if (rabbit.userId != owner) {
        throw ApiException('El registro no pertenece a la cuenta activa',
            code: 'owner_mismatch');
      }
      await transaction(() async {
        final existing = await (_db.select(_db.rabbits)
              ..where((t) => t.uuid.equals(rabbit.uuid)))
            .getSingleOrNull();
        if (existing != null &&
            (existing.userId != owner || existing.quarantineReason != null)) {
          throw ApiException('Identificador reservado por otro registro',
              code: 'owner_mismatch');
        }
        await _db
            .into(_db.rabbits)
            .insertOnConflictUpdate(_toCompanion(rabbit));
      });
      return;
    }
    await _db.into(_db.rabbits).insertOnConflictUpdate(_toCompanion(rabbit));
  }

  Future<void> removeByUuid(String uuid) async {
    checkSession();
    await (_db.delete(_db.rabbits)
          ..where((t) => _ownedRabbit(t) & t.uuid.equals(uuid)))
        .go();
  }

  Future<void> markDeleted(String uuid,
      {required RabbitSyncStatus status}) async {
    checkSession();
    await (_db.update(_db.rabbits)
          ..where((t) => _ownedRabbit(t) & t.uuid.equals(uuid)))
        .write(
      RabbitsCompanion(
        deletedAt: Value(_nowIso()),
        updatedAt: Value(_nowIso()),
        syncStatus: Value(status.storageValue),
      ),
    );
  }

  /// Replaces SYNCED rows with the remote snapshot; keeps pending local work.
  Future<void> persistSynced(List<Rabbit> rabbits) async {
    await transaction(() async {
      if (ownerId != null &&
          rabbits.any((rabbit) => rabbit.userId != ownerId)) {
        throw ApiException('La lista contiene registros de otra cuenta',
            code: 'owner_mismatch');
      }
      final existing =
          await (_db.select(_db.rabbits)..where(_ownedRabbit)).get();
      final pendingUuids = {
        for (final row in existing)
          if (row.syncStatus != RabbitSyncStatus.synced.storageValue) row.uuid,
      };
      final remoteUuids = rabbits.map((r) => r.uuid).toSet();

      for (final row in existing) {
        if (row.syncStatus == RabbitSyncStatus.synced.storageValue &&
            (ownerId == null || row.deletedAt == null) &&
            !remoteUuids.contains(row.uuid)) {
          checkSession();
          await (_db.delete(_db.rabbits)
                ..where((t) => _ownedRabbit(t) & t.uuid.equals(row.uuid)))
              .go();
        }
      }

      for (final rabbit in rabbits) {
        if (pendingUuids.contains(rabbit.uuid)) continue;
        if (ownerId != null) {
          final reserved = await (_db.select(_db.rabbits)
                ..where((t) =>
                    t.uuid.equals(rabbit.uuid) &
                    t.quarantineReason.isNotNull()))
              .getSingleOrNull();
          if (reserved != null) continue;
        }
        await upsert(rabbit.copyWith(syncStatus: RabbitSyncStatus.synced));
      }
    });
  }

  Future<List<SyncOperation>> readPendingOperations() async {
    checkSession();
    final rows = await (_db.select(_db.syncOperations)
          ..where((t) =>
              _ownedOperation(t) &
              t.status.equals(SyncOpStatus.pending.storageValue))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    return rows.map(_toOperation).toList();
  }

  Future<List<SyncOperation>> readRetryableOperations() async {
    checkSession();
    final rows = await (_db.select(_db.syncOperations)
          ..where(
            (t) =>
                _ownedOperation(t) &
                t.status.isIn([
                  SyncOpStatus.pending.storageValue,
                  SyncOpStatus.failed.storageValue,
                  SyncOpStatus.syncing.storageValue,
                ]),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    return rows.map(_toOperation).toList();
  }

  Future<void> markOperation({
    required int id,
    required SyncOpStatus status,
    int? attempts,
    String? lastError,
    String? serverSnapshot,
  }) async {
    checkSession();
    await (_db.update(_db.syncOperations)
          ..where((t) => _ownedOperation(t) & t.id.equals(id)))
        .write(
      SyncOperationsCompanion(
        status: Value(status.storageValue),
        attempts: attempts == null ? const Value.absent() : Value(attempts),
        lastError: Value(lastError),
        serverSnapshot: serverSnapshot == null
            ? const Value.absent()
            : Value(serverSnapshot),
      ),
    );
  }

  Future<List<SyncOperation>> readConflictOperations() async {
    checkSession();
    final rows = await (_db.select(_db.syncOperations)
          ..where((t) =>
              _ownedOperation(t) &
              t.status.equals(SyncOpStatus.conflict.storageValue))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    return rows.map(_toOperation).toList();
  }

  Future<SyncOperation?> readConflictForUuid(String uuid) async {
    checkSession();
    final row = await (_db.select(_db.syncOperations)
          ..where(
            (t) =>
                t.rabbitUuid.equals(uuid) &
                _ownedOperation(t) &
                t.status.equals(SyncOpStatus.conflict.storageValue),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _toOperation(row);
  }

  Future<void> enqueueOrCoalesce({
    required String rabbitUuid,
    required SyncOperationType type,
    required String payload,
    required int baseVersion,
    Rabbit? beforeUpdate,
  }) =>
      transaction(() => _enqueueOrCoalesce(
            rabbitUuid: rabbitUuid,
            type: type,
            payload: payload,
            baseVersion: baseVersion,
            beforeUpdate: beforeUpdate,
          ));

  Future<void> _enqueueOrCoalesce({
    required String rabbitUuid,
    required SyncOperationType type,
    required String payload,
    required int baseVersion,
    Rabbit? beforeUpdate,
  }) async {
    checkSession();
    final pending = await (_db.select(_db.syncOperations)
          ..where(
            (t) =>
                t.rabbitUuid.equals(rabbitUuid) &
                _ownedOperation(t) &
                t.status.equals(SyncOpStatus.pending.storageValue),
          ))
        .get();

    if (type == SyncOperationType.delete) {
      final creates = pending
          .where(
            (row) => row.operationType == SyncOperationType.create.storageValue,
          )
          .toList();
      final hasCreate = creates.length == 1 && creates.single.attempts == 0;
      if (hasCreate && ownerId != null) {
        final create = creates.single;
        final operationUuid = create.operationUuid;
        if (operationUuid == null) {
          throw StateError('Cannot cancel a Rabbit CREATE without identity');
        }
        await _db.customStatement('''
          INSERT INTO sync_create_cancellations
            (owner_id, operation_uuid, rabbit_uuid, reason, cancelled_at)
          VALUES (?, ?, ?, 'local_create_deleted', ?)
        ''', [ownerId, operationUuid, rabbitUuid, _nowIso()]);
        checkSession();
      }
      for (final row in pending) {
        // A previously attempted CREATE may already exist on the server.
        if (!hasCreate && creates.contains(row)) continue;
        checkSession();
        await (_db.delete(_db.syncOperations)
              ..where((t) => _ownedOperation(t) & t.id.equals(row.id)))
            .go();
      }
      if (hasCreate) {
        await removeByUuid(rabbitUuid);
        return;
      }
      await _insertOp(
        rabbitUuid: rabbitUuid,
        type: type,
        payload: payload,
        baseVersion: baseVersion,
      );
      return;
    }

    if (type == SyncOperationType.create) {
      final create = pending.where(
        (row) => row.operationType == SyncOperationType.create.storageValue,
      );
      if (create.isNotEmpty) {
        checkSession();
        await (_db.update(_db.syncOperations)
              ..where((t) => _ownedOperation(t) & t.id.equals(create.first.id)))
            .write(SyncOperationsCompanion(payload: Value(payload)));
        return;
      }
    }

    if (type == SyncOperationType.update) {
      final create = pending.where(
        (row) => row.operationType == SyncOperationType.create.storageValue,
      );
      if (create.isNotEmpty) {
        checkSession();
        await (_db.update(_db.syncOperations)
              ..where((t) => _ownedOperation(t) & t.id.equals(create.first.id)))
            .write(SyncOperationsCompanion(payload: Value(payload)));
        return;
      }
      final update = pending.where(
        (row) => row.operationType == SyncOperationType.update.storageValue,
      );
      if (update.isNotEmpty) {
        checkSession();
        await (_db.update(_db.syncOperations)
              ..where((t) => _ownedOperation(t) & t.id.equals(update.first.id)))
            .write(SyncOperationsCompanion(payload: Value(payload)));
        return;
      }
    }

    final operationUuid = await _insertOp(
      rabbitUuid: rabbitUuid,
      type: type,
      payload: payload,
      baseVersion: baseVersion,
    );
    final before = beforeUpdate;
    if (ownerId != null &&
        type == SyncOperationType.update &&
        before != null &&
        before.userId == ownerId &&
        before.uuid == rabbitUuid &&
        before.syncStatus == RabbitSyncStatus.synced &&
        before.id > 0) {
      await _db.customStatement('''
        INSERT INTO sync_rabbit_preimages
          (owner_id, operation_uuid, sex, status, knowledge)
        VALUES (?, ?, ?, ?, ?)
      ''', [
        ownerId,
        operationUuid,
        before.sex,
        before.status,
        before.genealogyKnowledge
      ]);
    }
  }

  Future<String> _insertOp({
    required String rabbitUuid,
    required SyncOperationType type,
    required String payload,
    required int baseVersion,
  }) async {
    final operationUuid = newLocalUuid();
    await _db.into(_db.syncOperations).insert(
          SyncOperationsCompanion.insert(
            rabbitUuid: rabbitUuid,
            operationType: type.storageValue,
            payload: payload,
            baseVersion: baseVersion,
            createdAt: _nowIso(),
            ownerId: Value(ownerId),
            operationUuid: Value(operationUuid),
            entityReferences: Value(jsonEncode([rabbitUuid])),
          ),
        );
    return operationUuid;
  }

  SyncOperation _toOperation(LocalSyncOperation row) {
    return SyncOperation(
      id: row.id,
      rabbitUuid: row.rabbitUuid,
      operationType: SyncOperationType.fromStorage(row.operationType),
      payload: row.payload,
      baseVersion: row.baseVersion,
      createdAt: row.createdAt,
      attempts: row.attempts,
      status: SyncOpStatus.fromStorage(row.status),
      lastError: row.lastError,
      serverSnapshot: row.serverSnapshot,
    );
  }

  Rabbit _toRabbit(LocalRabbit row) {
    return Rabbit(
      id: row.serverId ?? 0,
      uuid: row.uuid,
      userId: row.userId,
      name: row.name,
      breed: row.breed,
      sex: row.sex,
      birthDate: row.birthDate,
      weight: row.weight,
      status: row.status,
      notes: row.notes,
      genealogyKnowledge: row.genealogyKnowledge,
      version: row.version,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
      syncStatus: RabbitSyncStatus.fromStorage(row.syncStatus),
    );
  }

  RabbitsCompanion _toCompanion(Rabbit rabbit) {
    return RabbitsCompanion(
      uuid: Value(rabbit.uuid),
      serverId: Value(rabbit.id == 0 ? null : rabbit.id),
      userId: Value(rabbit.userId),
      name: Value(rabbit.name),
      breed: Value(rabbit.breed),
      sex: Value(rabbit.sex),
      birthDate: Value(rabbit.birthDate),
      weight: Value(rabbit.weight),
      status: Value(rabbit.status),
      notes: Value(rabbit.notes),
      genealogyKnowledge: Value(rabbit.genealogyKnowledge),
      createdAt: Value(rabbit.createdAt),
      updatedAt: Value(rabbit.updatedAt),
      version: Value(rabbit.version),
      deletedAt: Value(rabbit.deletedAt),
      syncStatus: Value(rabbit.syncStatus.storageValue),
    );
  }
}
