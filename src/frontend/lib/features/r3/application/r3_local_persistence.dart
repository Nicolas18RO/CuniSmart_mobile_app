import 'package:drift/drift.dart' show Value;

import '../../../core/errors/api_exception.dart';
import '../../../data/local/app_database.dart';
import '../../../domain/genealogy/parent_link.dart';
import '../../../models/local_uuid.dart';
import '../../../models/rabbit.dart';
import '../../../models/sync_operation.dart';
import '../../../models/sync_status.dart';
import '../../../services/auth_service.dart';
import '../data/r3_local_store.dart';

/// Mutations for E6.2. Read models and remote publication are separate concerns.
class R3LocalPersistence {
  R3LocalPersistence(this._store,
      {Future<bool> Function()? canAccess, DateTime Function()? clock})
      : _canAccess = canAccess,
        _clock = clock ?? DateTime.now;

  static R3LocalPersistence forSession(AppDatabase db, AuthService auth) {
    final owner = auth.ownerId;
    final generation = auth.generation;
    if (owner == null || !auth.localDataUnlocked) throw _invalidSession();
    return R3LocalPersistence(
      R3LocalStore(db,
          ownerId: owner,
          isCurrent: () =>
              auth.ownerId == owner &&
              auth.generation == generation &&
              auth.localDataUnlocked),
      canAccess: auth.canAccessLocally,
    );
  }

  final R3LocalStore _store;
  final Future<bool> Function()? _canAccess;
  final DateTime Function() _clock;

  static ApiException _invalidSession() =>
      ApiException('No hay una sesión autorizada', code: 'session_changed');

  Future<T> _run<T>(Future<T> Function() action) =>
      _store.transaction(() async {
        if (_canAccess != null && !await _canAccess()) throw _invalidSession();
        final result = await action();
        if (_canAccess != null && !await _canAccess()) throw _invalidSession();
        return result;
      });

  Future<List<StoredParentLink>> parentLinks() => _run(_store.parentLinks);

  Future<StoredReproductiveEvent?> event(String uuid) =>
      _run(() => _store.event(uuid));

  Future<StoredParentLink> assignParent({
    required String childUuid,
    required String parentUuid,
    required ParentRole role,
    int? version,
  }) =>
      _run(() async {
        final child = await _requireRabbit(childUuid);
        final parent = await _requireRabbit(parentUuid);
        final links = await _store.parentLinks();
        final latest = _latestRole(links, childUuid, role);
        final decision = ParentLinkRules.assign(
          child: _subject(child),
          parent: _subject(parent),
          role: role,
          activeLinks: links.map(_domainLink).toList(),
          version: version,
        );
        final link = _accepted(decision);
        final current = latest?.deletedAt == null ? latest : null;
        final now = _clock().toUtc().toIso8601String();
        final row = StoredParentLink(
          uuid: current?.uuid ?? newLocalUuid(),
          ownerId: _store.ownerId,
          childUuid: link.childUuid,
          parentUuid: link.parentUuid,
          role: role.storageValue,
          version: link.version,
          createdAt: current?.createdAt ?? now,
          updatedAt: now,
        );
        await _store.saveParent(
          row,
          predecessorUuid: latest?.uuid,
          type: current == null
              ? SyncOperationType.create
              : SyncOperationType.update,
          baseVersion: current?.version ?? 0,
          participants: [child, parent],
        );
        return row;
      });

  Future<StoredParentLink> clearParent({
    required String childUuid,
    required ParentRole role,
    required int version,
  }) =>
      _run(() async {
        final child = await _requireRabbit(childUuid);
        final links = await _store.parentLinks();
        final current = _latestRole(links, childUuid, role);
        if (current == null || current.deletedAt != null) {
          throw ApiException('No hay un vínculo activo',
              code: 'version_conflict');
        }
        final parent = await _store.rabbit(current.parentUuid);
        final now = _clock().toUtc();
        final link = _accepted(ParentLinkRules.clear(
          child: _subject(child),
          parent: parent != null
              ? _subject(parent)
              : GenealogySubject(
                  uuid: current.parentUuid,
                  sex: '',
                  ownerId: current.ownerId,
                  deleted: true),
          role: role,
          links: links.map(_domainLink).toList(),
          version: version,
          deletedAt: now,
        ));
        final timestamp = now.toIso8601String();
        final row = current.copyWith(
            version: link.version,
            updatedAt: timestamp,
            deletedAt: Value(timestamp));
        await _store.saveParent(
          row,
          type: SyncOperationType.delete,
          baseVersion: version,
          participants: [child, if (parent != null) parent],
        );
        return row;
      });

  Future<StoredReproductiveEvent> createEvent({
    required String maleUuid,
    required String femaleUuid,
    required String matingDate,
    String notes = '',
  }) =>
      _run(() async {
        final participants = await _eventPair(maleUuid, femaleUuid);
        _validateDate(matingDate);
        final now = _clock().toUtc().toIso8601String();
        final row = StoredReproductiveEvent(
          uuid: newLocalUuid(),
          ownerId: _store.ownerId,
          maleUuid: maleUuid,
          femaleUuid: femaleUuid,
          matingDate: matingDate,
          notes: _validateNotes(notes),
          version: 1,
          createdAt: now,
          updatedAt: now,
        );
        await _store.saveEvent(row,
            type: SyncOperationType.create,
            baseVersion: 0,
            participants: participants);
        return row;
      });

  Future<StoredReproductiveEvent> updateEvent({
    required String uuid,
    required int version,
    String? matingDate,
    String? notes,
  }) =>
      _run(() async {
        final current = await _activeEvent(uuid, version);
        final participants =
            await _eventPair(current.maleUuid, current.femaleUuid);
        if (matingDate != null) _validateDate(matingDate);
        final row = current.copyWith(
          matingDate: matingDate,
          notes: notes == null ? null : _validateNotes(notes),
          version: version + 1,
          updatedAt: _clock().toUtc().toIso8601String(),
        );
        await _store.saveEvent(row,
            type: SyncOperationType.update,
            baseVersion: version,
            participants: participants);
        return row;
      });

  Future<StoredReproductiveEvent> deleteEvent({
    required String uuid,
    required int version,
  }) =>
      _run(() async {
        final current = await _activeEvent(uuid, version);
        final now = _clock().toUtc().toIso8601String();
        final row = current.copyWith(
            version: version + 1, updatedAt: now, deletedAt: Value(now));
        await _store.saveEvent(row,
            type: SyncOperationType.delete,
            baseVersion: version,
            participants: const []);
        return row;
      });

  Future<StoredReproductiveEvent> _activeEvent(String uuid, int version) async {
    final current = await _store.event(uuid);
    if (current == null || current.deletedAt != null) {
      throw ApiException('Evento local inexistente');
    }
    if (current.version != version) {
      throw ApiException('La versión del evento cambió',
          code: 'version_conflict');
    }
    return current;
  }

  Future<List<Rabbit>> _eventPair(String maleUuid, String femaleUuid) async {
    final male = await _requireRabbit(maleUuid);
    final female = await _requireRabbit(femaleUuid);
    if (male.uuid == female.uuid ||
        male.sex != 'male' ||
        female.sex != 'female' ||
        male.status != 'active' ||
        female.status != 'active' ||
        male.deletedAt != null ||
        female.deletedAt != null) {
      throw ApiException('El evento requiere un macho y una hembra activos');
    }
    return [male, female];
  }

  Future<Rabbit> _requireRabbit(String uuid) async {
    final rabbit = await _store.rabbit(uuid);
    if (rabbit == null || !_subject(rabbit).hasUuid) {
      throw ApiException('Animal no disponible en la cuenta');
    }
    return rabbit;
  }

  GenealogySubject _subject(Rabbit rabbit) => GenealogySubject(
        uuid: rabbit.uuid,
        sex: rabbit.sex,
        ownerId: rabbit.userId,
        deleted: rabbit.deletedAt != null,
        knowledge: rabbit.genealogyKnowledge,
      );

  ParentLink _domainLink(StoredParentLink row) => ParentLink(
        childUuid: row.childUuid, parentUuid: row.parentUuid,
        role: ParentRole.fromStorage(row.role)!, version: row.version,
        deletedAt:
            row.deletedAt == null ? null : DateTime.parse(row.deletedAt!),
        // The domain validator uses the edge and version. Outbox tracks publication.
        syncStatus: RabbitSyncStatus.synced,
      );

  StoredParentLink? _latestRole(
      List<StoredParentLink> links, String child, ParentRole role) {
    StoredParentLink? latest;
    for (final row in links) {
      if (row.childUuid == child &&
          row.role == role.storageValue &&
          (latest == null || row.version > latest.version)) latest = row;
    }
    return latest;
  }

  ParentLink _accepted(ParentLinkDecision decision) =>
      decision.link ??
      (throw ApiException('Relación genealógica inválida',
          code: decision.violation!.name));

  String _validateNotes(String notes) {
    final trimmed = notes.trim();
    if (trimmed.runes.length > 4000) {
      throw ApiException('Las notas no pueden superar 4000 caracteres');
    }
    return trimmed;
  }

  void _validateDate(String date) {
    final parsed = DateTime.tryParse('${date}T00:00:00Z');
    if (parsed == null ||
        date.length != 10 ||
        parsed.year < 1 ||
        !parsed.toIso8601String().startsWith('${date}T') ||
        parsed.add(const Duration(days: 31)).year > 9999) {
      throw ApiException('La fecha de monta no es válida');
    }
  }
}
