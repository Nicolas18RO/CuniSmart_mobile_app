import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../models/rabbit.dart';
import '../models/sync_operation.dart';
import '../models/sync_status.dart';

/// Drift access for rabbits and the sync queue. Mapping lives here, not in widgets.
class RabbitLocalStore {
  RabbitLocalStore(this._db);

  final AppDatabase _db;

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  Future<List<Rabbit>> readActive() async {
    final rows = await (_db.select(_db.rabbits)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    return rows.map(_toRabbit).toList();
  }

  Future<Rabbit?> readByUuid(String uuid) async {
    final row = await (_db.select(_db.rabbits)
          ..where((t) => t.uuid.equals(uuid)))
        .getSingleOrNull();
    return row == null ? null : _toRabbit(row);
  }

  Future<void> upsert(Rabbit rabbit) async {
    await _db.into(_db.rabbits).insertOnConflictUpdate(_toCompanion(rabbit));
  }

  Future<void> removeByUuid(String uuid) async {
    await (_db.delete(_db.rabbits)..where((t) => t.uuid.equals(uuid))).go();
  }

  Future<void> markDeleted(String uuid,
      {required RabbitSyncStatus status}) async {
    await (_db.update(_db.rabbits)..where((t) => t.uuid.equals(uuid))).write(
      RabbitsCompanion(
        deletedAt: Value(_nowIso()),
        updatedAt: Value(_nowIso()),
        syncStatus: Value(status.storageValue),
      ),
    );
  }

  /// Replaces SYNCED rows with the remote snapshot; keeps pending local work.
  Future<void> persistSynced(List<Rabbit> rabbits) async {
    await _db.transaction(() async {
      final existing = await _db.select(_db.rabbits).get();
      final pendingUuids = {
        for (final row in existing)
          if (row.syncStatus != RabbitSyncStatus.synced.storageValue) row.uuid,
      };
      final remoteUuids = rabbits.map((r) => r.uuid).toSet();

      for (final row in existing) {
        if (row.syncStatus == RabbitSyncStatus.synced.storageValue &&
            !remoteUuids.contains(row.uuid)) {
          await (_db.delete(_db.rabbits)..where((t) => t.uuid.equals(row.uuid)))
              .go();
        }
      }

      for (final rabbit in rabbits) {
        if (pendingUuids.contains(rabbit.uuid)) continue;
        await _db.into(_db.rabbits).insertOnConflictUpdate(
              _toCompanion(
                  rabbit.copyWith(syncStatus: RabbitSyncStatus.synced)),
            );
      }
    });
  }

  Future<List<SyncOperation>> readPendingOperations() async {
    final rows = await (_db.select(_db.syncOperations)
          ..where((t) => t.status.equals(SyncOpStatus.pending.storageValue))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    return rows.map(_toOperation).toList();
  }

  Future<List<SyncOperation>> readRetryableOperations() async {
    final rows = await (_db.select(_db.syncOperations)
          ..where(
            (t) => t.status.isIn([
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
    await (_db.update(_db.syncOperations)..where((t) => t.id.equals(id))).write(
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
    final rows = await (_db.select(_db.syncOperations)
          ..where((t) => t.status.equals(SyncOpStatus.conflict.storageValue))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    return rows.map(_toOperation).toList();
  }

  Future<SyncOperation?> readConflictForUuid(String uuid) async {
    final row = await (_db.select(_db.syncOperations)
          ..where(
            (t) =>
                t.rabbitUuid.equals(uuid) &
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
  }) async {
    final pending = await (_db.select(_db.syncOperations)
          ..where(
            (t) =>
                t.rabbitUuid.equals(rabbitUuid) &
                t.status.equals(SyncOpStatus.pending.storageValue),
          ))
        .get();

    if (type == SyncOperationType.delete) {
      final hasCreate = pending.any(
        (row) => row.operationType == SyncOperationType.create.storageValue,
      );
      for (final row in pending) {
        await (_db.delete(_db.syncOperations)
              ..where((t) => t.id.equals(row.id)))
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
        await (_db.update(_db.syncOperations)
              ..where((t) => t.id.equals(create.first.id)))
            .write(SyncOperationsCompanion(payload: Value(payload)));
        return;
      }
    }

    if (type == SyncOperationType.update) {
      final create = pending.where(
        (row) => row.operationType == SyncOperationType.create.storageValue,
      );
      if (create.isNotEmpty) {
        await (_db.update(_db.syncOperations)
              ..where((t) => t.id.equals(create.first.id)))
            .write(SyncOperationsCompanion(payload: Value(payload)));
        return;
      }
      final update = pending.where(
        (row) => row.operationType == SyncOperationType.update.storageValue,
      );
      if (update.isNotEmpty) {
        await (_db.update(_db.syncOperations)
              ..where((t) => t.id.equals(update.first.id)))
            .write(SyncOperationsCompanion(payload: Value(payload)));
        return;
      }
    }

    await _insertOp(
      rabbitUuid: rabbitUuid,
      type: type,
      payload: payload,
      baseVersion: baseVersion,
    );
  }

  Future<void> _insertOp({
    required String rabbitUuid,
    required SyncOperationType type,
    required String payload,
    required int baseVersion,
  }) async {
    await _db.into(_db.syncOperations).insert(
          SyncOperationsCompanion.insert(
            rabbitUuid: rabbitUuid,
            operationType: type.storageValue,
            payload: payload,
            baseVersion: baseVersion,
            createdAt: _nowIso(),
          ),
        );
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
      createdAt: Value(rabbit.createdAt),
      updatedAt: Value(rabbit.updatedAt),
      version: Value(rabbit.version),
      deletedAt: Value(rabbit.deletedAt),
      syncStatus: Value(rabbit.syncStatus.storageValue),
    );
  }
}
