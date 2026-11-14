import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../../data/local/sync_dependency_evaluator.dart';
import '../../../models/local_uuid.dart';
import '../../../models/rabbit.dart';
import '../../../models/sync_operation.dart';
import '../../../models/sync_status.dart';
import '../../../services/rabbit_local_store.dart';

/// Account-scoped storage for R3 and its entries in the existing outbox.
class R3LocalStore {
  R3LocalStore(this._db,
      {required this.ownerId, required bool Function() isCurrent})
      : _rabbits =
            RabbitLocalStore.accountScopes(_db).forOwner(ownerId, isCurrent) {
    if (ownerId <= 0) throw ArgumentError.value(ownerId, 'ownerId');
  }

  static const parentEntity = 'PARENT_LINK';
  static const eventEntity = 'REPRODUCTIVE_EVENT';

  final AppDatabase _db;
  final RabbitLocalStore _rabbits;
  final int ownerId;

  Future<T> transaction<T>(Future<T> Function() action) =>
      _rabbits.transaction(action);

  Future<Rabbit?> rabbit(String uuid) => _rabbits.readByUuid(uuid);

  Future<List<StoredParentLink>> parentLinks({
    String? childUuid,
    String? parentUuid,
    String? role,
    bool includeDeleted = true,
  }) async {
    _rabbits.checkSession();
    final links = await (_db.select(_db.localParentLinks)
          ..where((t) =>
              t.ownerId.equals(ownerId) &
              (childUuid == null
                  ? const Constant(true)
                  : t.childUuid.equals(childUuid)) &
              (parentUuid == null
                  ? const Constant(true)
                  : t.parentUuid.equals(parentUuid)) &
              (role == null ? const Constant(true) : t.role.equals(role)) &
              (includeDeleted ? const Constant(true) : t.deletedAt.isNull()))
          ..orderBy([
            (t) => OrderingTerm.asc(t.version),
            (t) => OrderingTerm.asc(t.uuid)
          ]))
        .get();
    _rabbits.checkSession();
    return links;
  }

  Future<List<StoredReproductiveEvent>> events({
    String? participantUuid,
    bool? asMale,
    String? from,
    String? to,
    bool includeDeleted = false,
  }) async {
    _rabbits.checkSession();
    final rows = await (_db.select(_db.localReproductiveEvents)
          ..where((t) {
            final participant = switch ((participantUuid, asMale)) {
              (final String id, true) => t.maleUuid.equals(id),
              (final String id, false) => t.femaleUuid.equals(id),
              (final String id, null) =>
                t.maleUuid.equals(id) | t.femaleUuid.equals(id),
              _ => const Constant(true),
            };
            return t.ownerId.equals(ownerId) &
                participant &
                (includeDeleted ? const Constant(true) : t.deletedAt.isNull()) &
                (from == null
                    ? const Constant(true)
                    : t.matingDate.isBiggerOrEqualValue(from)) &
                (to == null
                    ? const Constant(true)
                    : t.matingDate.isSmallerOrEqualValue(to));
          })
          ..orderBy([
            (t) => OrderingTerm.asc(t.matingDate),
            (t) => OrderingTerm.asc(t.uuid)
          ]))
        .get();
    _rabbits.checkSession();
    return rows;
  }

  Future<Map<String, Rabbit>> rabbitReferences(Set<String> uuids) async {
    _rabbits.checkSession();
    final result = <String, Rabbit>{};
    // Bulk query the existing scoped store, including tombstones.
    for (final rabbit in await _rabbits.readByUuids(uuids)) {
      result[rabbit.uuid] = rabbit;
    }
    _rabbits.checkSession();
    return result;
  }

  Future<Map<String, LocalSyncOperation>> parentIntents() async {
    _rabbits.checkSession();
    final rows = await (_db.select(_db.syncOperations)
          ..where((t) =>
              t.ownerId.equals(ownerId) &
              t.entityType.equals(parentEntity) &
              t.quarantineReason.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    _rabbits.checkSession();
    return {for (final row in rows) row.rabbitUuid: row};
  }

  Future<StoredReproductiveEvent?> event(String uuid) async {
    _rabbits.checkSession();
    final row = await (_db.select(_db.localReproductiveEvents)
          ..where((t) => t.ownerId.equals(ownerId) & t.uuid.equals(uuid)))
        .getSingleOrNull();
    _rabbits.checkSession();
    return row;
  }

  Future<void> saveParent(
    StoredParentLink row, {
    required SyncOperationType type,
    required int baseVersion,
    required List<Rabbit> participants,
    String? predecessorUuid,
  }) =>
      transaction(() async {
        await _writeParent(row, create: type == SyncOperationType.create);
        await _record(
          entity: parentEntity,
          uuid: row.uuid,
          predecessorUuid: predecessorUuid,
          type: type,
          baseVersion: baseVersion,
          payload: {
            'child_uuid': row.childUuid,
            'parent_uuid': row.parentUuid,
            'role': row.role,
            if (baseVersion > 0) 'version': baseVersion,
          },
          participants: participants,
          references: [row.childUuid, row.parentUuid],
          timestamp: row.updatedAt,
        );
      });

  Future<void> saveEvent(
    StoredReproductiveEvent row, {
    required SyncOperationType type,
    required int baseVersion,
    required List<Rabbit> participants,
  }) =>
      transaction(() async {
        await _writeEvent(row, create: type == SyncOperationType.create);
        await _record(
          entity: eventEntity,
          uuid: row.uuid,
          type: type,
          baseVersion: baseVersion,
          payload: {
            'uuid': row.uuid,
            'male_uuid': row.maleUuid,
            'female_uuid': row.femaleUuid,
            'mating_date': row.matingDate,
            'notes': row.notes,
            if (baseVersion > 0) 'version': baseVersion,
          },
          participants: participants,
          references: [row.maleUuid, row.femaleUuid],
          timestamp: row.updatedAt,
        );
      });

  Future<void> _writeParent(StoredParentLink row,
      {required bool create}) async {
    _checkOwner(row.ownerId);
    if (create) {
      await _db.into(_db.localParentLinks).insert(row);
      return;
    }
    final count = await (_db.update(_db.localParentLinks)
          ..where((t) => t.ownerId.equals(ownerId) & t.uuid.equals(row.uuid)))
        .write(row.toCompanion(false));
    if (count != 1) throw StateError('Vínculo local inexistente');
  }

  Future<void> _writeEvent(StoredReproductiveEvent row,
      {required bool create}) async {
    _checkOwner(row.ownerId);
    if (create) {
      await _db.into(_db.localReproductiveEvents).insert(row);
      return;
    }
    final count = await (_db.update(_db.localReproductiveEvents)
          ..where((t) => t.ownerId.equals(ownerId) & t.uuid.equals(row.uuid)))
        .write(row.toCompanion(false));
    if (count != 1) throw StateError('Evento local inexistente');
  }

  void _checkOwner(int owner) {
    _rabbits.checkSession();
    if (owner != ownerId) {
      throw StateError('El registro pertenece a otra cuenta');
    }
  }

  Future<void> _record({
    required String entity,
    required String uuid,
    String? predecessorUuid,
    required SyncOperationType type,
    required int baseVersion,
    required Map<String, Object> payload,
    required List<Rabbit> participants,
    required List<String> references,
    required String timestamp,
  }) async {
    _rabbits.checkSession();
    final dependencies = <String>{};
    final predecessor = await _latest(entity, predecessorUuid ?? uuid);
    if (predecessor != null) dependencies.add(_operationIdentity(predecessor));

    final requirements = rabbitRequirements(entity, type.storageValue, payload);
    for (final rabbit in participants) {
      _checkOwner(rabbit.userId);
      final requirement = requirements?[rabbit.uuid];
      if (requirement == null) continue;
      if (rabbit.syncStatus == RabbitSyncStatus.pendingUpdate) {
        final update = await _latest('RABBIT', rabbit.uuid);
        if (update?.operationType == 'UPDATE' &&
            update?.operationUuid != null) {
          final before = await _db.customSelect(
            'SELECT sex, status, knowledge FROM sync_rabbit_preimages '
            'WHERE owner_id = ? AND operation_uuid = ?',
            variables: [Variable(ownerId), Variable(update!.operationUuid!)],
          ).getSingleOrNull();
          final local = await (_db.select(_db.rabbits)
                ..where((t) =>
                    t.userId.equals(ownerId) & t.uuid.equals(rabbit.uuid)))
              .getSingleOrNull();
          if (before != null &&
              local != null &&
              requirement(local) &&
              !requirement(local.copyWith(
                sex: before.read<String>('sex'),
                status: before.read<String>('status'),
                genealogyKnowledge: before.read<String>('knowledge'),
              ))) {
            dependencies.add(_operationIdentity(update));
          }
        }
      }
      if (rabbit.syncStatus != RabbitSyncStatus.pendingCreate) continue;
      final create = await _latest('RABBIT', rabbit.uuid, createOnly: true);
      if (create == null) {
        throw StateError('Alta local sin intención publicable');
      }
      dependencies.add(_operationIdentity(create));
    }
    _rabbits.checkSession();
    await _db.into(_db.syncOperations).insert(SyncOperationsCompanion.insert(
          // v4 uses this legacy column as the entity identifier, qualified by entityType.
          rabbitUuid: uuid,
          ownerId: Value(ownerId),
          operationUuid: Value(newLocalUuid()),
          entityType: Value(entity),
          dependencies: Value(jsonEncode(dependencies.toList())),
          entityReferences: Value(jsonEncode(references.toSet().toList())),
          operationType: type.storageValue,
          baseVersion: baseVersion,
          payload: jsonEncode(payload),
          createdAt: timestamp,
        ));
  }

  Future<LocalSyncOperation?> _latest(String entity, String uuid,
          {bool createOnly = false}) =>
      (_db.select(_db.syncOperations)
            ..where((t) =>
                t.ownerId.equals(ownerId) &
                t.entityType.equals(entity) &
                t.rabbitUuid.equals(uuid) &
                t.quarantineReason.isNull() &
                (createOnly
                    ? t.operationType
                        .equals(SyncOperationType.create.storageValue)
                    : const Constant(true)))
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(1))
          .getSingleOrNull()
          .then(
            (row) =>
                row?.status == SyncOpStatus.completed.storageValue ? null : row,
          );

  String _operationIdentity(LocalSyncOperation operation) =>
      operation.operationUuid ?? (throw StateError('Intención sin UUID'));
}
