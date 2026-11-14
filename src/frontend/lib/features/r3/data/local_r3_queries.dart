import 'dart:collection';

import '../../../core/errors/api_exception.dart';
import '../../../data/local/app_database.dart';
import '../../../domain/genealogy/kinship.dart';
import '../../../domain/genealogy/parent_link.dart';
import '../../../models/rabbit.dart';
import '../../../models/sync_operation.dart';
import '../../../models/sync_status.dart';
import '../../../services/auth_service.dart';
import '../domain/r3_local_results.dart';
import 'r3_local_store.dart';

/// Local R3 read contract. The remote DTOs require facts a local copy may lack.
class LocalR3Queries {
  LocalR3Queries(this._store, {Future<bool> Function()? canAccess})
      : _canAccess = canAccess;

  factory LocalR3Queries.forSession(AppDatabase db, AuthService auth) {
    final owner = auth.ownerId;
    final generation = auth.generation;
    if (owner == null || !auth.localDataUnlocked) throw _invalidSession();
    return LocalR3Queries(
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

  static ApiException _invalidSession() =>
      ApiException('No hay una sesión autorizada', code: 'session_changed');

  Future<T> _read<T>(Future<T> Function() query) async {
    try {
      return await _store.transaction(() async {
        if (_canAccess != null && !await _canAccess()) throw _invalidSession();
        final result = await query();
        if (_canAccess != null && !await _canAccess()) throw _invalidSession();
        return result;
      });
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('No se pudo leer la información local R3',
          code: 'local_read_failed');
    }
  }

  Future<List<LocalParentRelation>> parents(String childUuid,
          {ParentRole? role, bool includeDeleted = false}) =>
      _read(() async => _relations(await _store.parentLinks(
          childUuid: childUuid,
          role: role?.storageValue,
          includeDeleted: includeDeleted)));

  Future<List<LocalParentRelation>> children(String parentUuid,
          {ParentRole? role, bool includeDeleted = false}) =>
      _read(() async => _relations(await _store.parentLinks(
          parentUuid: parentUuid,
          role: role?.storageValue,
          includeDeleted: includeDeleted)));

  Future<List<LocalParentRelation>> _relations(
      List<StoredParentLink> rows) async {
    final rabbits = await _store.rabbitReferences({
      for (final row in rows) ...[row.childUuid, row.parentUuid],
    });
    final intents = await _store.parentIntents();
    return List.unmodifiable(
        rows.map((row) => _relation(row, rabbits, intents)));
  }

  Future<List<LocalReproductiveRecord>> events({
    String? participantUuid,
    ReproductiveRole? role,
    String? from,
    String? to,
    bool includeDeleted = false,
  }) =>
      _read(() async {
        if (role != null && participantUuid == null) {
          throw ApiException('El rol requiere un participante');
        }
        _validateRange(from, to);
        return _events(
            participantUuid: participantUuid,
            role: role,
            from: from,
            to: to,
            includeDeleted: includeDeleted);
      });

  Future<LocalReproductiveRecord?> event(String uuid,
          {bool includeDeleted = false}) =>
      _read(() async {
        final row = await _store.event(uuid);
        if (row == null || (!includeDeleted && row.deletedAt != null)) {
          return null;
        }
        final rabbits =
            await _store.rabbitReferences({row.maleUuid, row.femaleUuid});
        return _event(row, rabbits);
      });

  Future<List<LocalReproductiveRecord>> _events({
    String? participantUuid,
    ReproductiveRole? role,
    String? from,
    String? to,
    bool includeDeleted = false,
  }) async {
    final rows = await _store.events(
        participantUuid: participantUuid,
        asMale: role == null ? null : role == ReproductiveRole.male,
        from: from,
        to: to,
        includeDeleted: includeDeleted);
    final rabbits = await _store.rabbitReferences({
      for (final row in rows) ...[row.maleUuid, row.femaleUuid],
    });
    return List.unmodifiable(rows.map((row) => _event(row, rabbits)));
  }

  Future<List<LocalCalendarEntry>> calendar(String start, String end,
          {required String today}) =>
      _read(() async {
        final from = _civil(start);
        final to = _civil(end);
        final reference = _civil(today);
        final days = to.difference(from).inDays;
        if (days < 0 || days > 366) {
          throw ApiException('Intervalo de calendario inválido');
        }
        final rows = await _events(
          from: _date(from.subtract(_gestation).isBefore(DateTime.utc(1))
              ? DateTime.utc(1)
              : from.subtract(_gestation)),
          to: _date(to.subtract(_gestation).isBefore(DateTime.utc(1))
              ? DateTime.utc(1)
              : to.subtract(_gestation)),
        );
        return List.unmodifiable([
          for (final row in rows)
            if (row.estimatedBirthDate.compareTo(start) >= 0 &&
                row.estimatedBirthDate.compareTo(end) <= 0)
              LocalCalendarEntry(row,
                  _civil(row.estimatedBirthDate).difference(reference).inDays),
        ]);
      });

  static const _gestation = Duration(days: 31);

  void _validateRange(String? from, String? to) {
    final start = from == null ? null : _civil(from);
    final end = to == null ? null : _civil(to);
    if (start != null && end != null && start.isAfter(end)) {
      throw ApiException('Intervalo de fechas inválido');
    }
  }

  DateTime _civil(String value) {
    final date = DateTime.tryParse('${value}T00:00:00Z');
    if (date == null ||
        date.year < 1 ||
        date.year > 9999 ||
        _date(date) != value) {
      throw ApiException('Fecha civil inválida');
    }
    return date;
  }

  String _date(DateTime date) => date.toIso8601String().split('T').first;

  LocalRabbitReference _reference(String uuid, Map<String, Rabbit> rabbits) =>
      LocalRabbitReference(uuid, rabbits[uuid]);

  LocalReproductiveRecord _event(
          StoredReproductiveEvent row, Map<String, Rabbit> rabbits) =>
      LocalReproductiveRecord(
          uuid: row.uuid,
          ownerId: row.ownerId,
          male: _reference(row.maleUuid, rabbits),
          female: _reference(row.femaleUuid, rabbits),
          matingDate: row.matingDate,
          estimatedBirthDate: _date(_civil(row.matingDate).add(_gestation)),
          notes: row.notes,
          version: row.version,
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt);

  LocalParentRelation _relation(
          StoredParentLink row,
          Map<String, Rabbit> rabbits,
          Map<String, LocalSyncOperation> intents) =>
      LocalParentRelation(
          uuid: row.uuid,
          ownerId: row.ownerId,
          link: ParentLink(
              childUuid: row.childUuid,
              parentUuid: row.parentUuid,
              role: ParentRole.fromStorage(row.role)!,
              version: row.version,
              deletedAt:
                  row.deletedAt == null ? null : DateTime.parse(row.deletedAt!),
              syncStatus: _parentSyncStatus(intents[row.uuid])),
          child: _reference(row.childUuid, rabbits),
          parent: _reference(row.parentUuid, rabbits),
          createdAt: row.createdAt,
          updatedAt: row.updatedAt);

  RabbitSyncStatus _parentSyncStatus(LocalSyncOperation? intent) {
    if (intent == null ||
        intent.status == SyncOpStatus.completed.storageValue) {
      return RabbitSyncStatus.synced;
    }
    if (intent.status == SyncOpStatus.conflict.storageValue) {
      return RabbitSyncStatus.conflict;
    }
    return switch (SyncOperationType.fromStorage(intent.operationType)) {
      SyncOperationType.create => RabbitSyncStatus.pendingCreate,
      SyncOperationType.update => RabbitSyncStatus.pendingUpdate,
      SyncOperationType.delete => RabbitSyncStatus.pendingDelete,
    };
  }

  /// Ancestor coverage is independent of how many descendant edges are cached.
  Future<LocalGenealogy> genealogy(List<String> roots,
          {int? maxDepth,
          bool descendants = false,
          bool includeDeleted = false}) =>
      _read(() async {
        if (roots.isEmpty ||
            roots.length > 2 ||
            (maxDepth != null && maxDepth < 0)) {
          throw ApiException('Consulta genealógica inválida');
        }
        final rows = await _store.parentLinks();
        final active = <String, List<StoredParentLink>>{};
        final history = <String, List<StoredParentLink>>{};
        final incoming = <String, List<StoredParentLink>>{};
        for (final row in rows) {
          if (row.deletedAt != null) {
            if (includeDeleted) {
              final key = descendants ? row.parentUuid : row.childUuid;
              history.putIfAbsent(key, () => []).add(row);
            }
            continue;
          }
          active.putIfAbsent(row.childUuid, () => []).add(row);
          if (descendants) {
            incoming.putIfAbsent(row.parentUuid, () => []).add(row);
          }
        }

        final depth = <String, int>{for (final root in roots) root: 0};
        final pending = Queue<String>.of(depth.keys);
        final selected = <StoredParentLink>{};
        final deleted = <StoredParentLink>{};
        var depthExplored = 0;
        var depthLimited = false;
        while (pending.isNotEmpty) {
          final uuid = pending.removeFirst();
          final level = depth[uuid]!;
          depthExplored = level;
          deleted.addAll(history[uuid] ?? const []);
          final next = descendants ? incoming[uuid] : active[uuid];
          if (next == null) continue;
          for (final edge in next) {
            final target = descendants ? edge.childUuid : edge.parentUuid;
            if (maxDepth != null &&
                level >= maxDepth &&
                !depth.containsKey(target)) {
              depthLimited = true;
              continue;
            }
            selected.add(edge);
            if (!depth.containsKey(target)) {
              depth[target] = level + 1;
              pending.add(target);
            }
          }
        }

        final rabbits = await _store.rabbitReferences({
          ...depth.keys,
          for (final edge in deleted) ...[edge.childUuid, edge.parentUuid],
        });
        final nodes = {
          for (final uuid in depth.keys) uuid: _reference(uuid, rabbits)
        };
        final parents = <String, Map<ParentRole, String>>{};
        for (final edge in selected) {
          parents.putIfAbsent(edge.childUuid,
              () => {})[ParentRole.fromStorage(edge.role)!] = edge.parentUuid;
        }
        final unknown = <String, List<ParentRole>>{};
        final founders = <String>{};
        final herd = <String, KinshipAnimal>{};
        final cycle = _hasCycle(nodes.keys, parents);
        var inconsistent = cycle;
        for (final node in nodes.values) {
          if (!node.usable) continue;
          final rabbit = node.rabbit!;
          final known = parents[node.uuid] ?? const <ParentRole, String>{};
          final hasActive = active[node.uuid]?.isNotEmpty ?? false;
          final founder = rabbit.genealogyKnowledge == 'FOUNDER';
          if (founder && hasActive) inconsistent = true;
          if (founder && !hasActive) {
            founders.add(node.uuid);
          } else if (!descendants) {
            final missingRoles = ParentRole.values
                .where((role) => !known.containsKey(role))
                .toList();
            if (missingRoles.isNotEmpty) unknown[node.uuid] = missingRoles;
          }
          if (descendants) continue;
          String? availableParent(ParentRole role) {
            final id = known[role];
            return nodes[id]?.usable == true ? id : null;
          }

          final father = availableParent(ParentRole.father);
          final mother = availableParent(ParentRole.mother);
          // The stored knowledge stays intact. The input describes only usable local facts.
          final knowledge = founder
              ? 'FOUNDER'
              : father != null && mother != null
                  ? 'RECORDED'
                  : 'UNKNOWN';
          herd[node.uuid] = KinshipAnimal(
              uuid: node.uuid,
              name: rabbit.name,
              sex: rabbit.sex,
              knowledge: knowledge,
              father: father,
              mother: mother);
        }
        final missingRoot = roots.any((uuid) => nodes[uuid]?.usable != true);
        final incomplete = descendants ||
            depthLimited ||
            unknown.isNotEmpty ||
            nodes.values.any((n) => !n.usable);
        final coverage = inconsistent
            ? GenealogyCoverage.inconsistent
            : missingRoot
                ? GenealogyCoverage.unavailable
                : incomplete
                    ? GenealogyCoverage.incomplete
                    : GenealogyCoverage.complete;
        final evaluation = !descendants && roots.length == 2
            ? inconsistent || missingRoot
                ? KinshipResult(
                    status: 'NO_CALCULABLE',
                    relationship: null,
                    expectedInbreeding: null,
                    riskLevel: 'NO_CALCULABLE',
                    commonAncestors: const [],
                    reason: inconsistent
                        ? 'INCONSISTENT_GENEALOGY'
                        : insufficientGenealogyReason,
                    unknownBranches: List.unmodifiable(nodes.values
                        .where((n) => !n.usable)
                        .map((n) => n.uuid)))
                : evaluateKinship(roots.first, roots.last, herd)
            : null;
        final intents = await _store.parentIntents();
        return LocalGenealogy(
            coverage: coverage,
            roots: roots,
            nodes: nodes,
            links: selected.map((row) => _relation(row, rabbits, intents)),
            deletedLinks:
                deleted.map((row) => _relation(row, rabbits, intents)),
            unknownParents: unknown,
            confirmedFounders: founders,
            depthExplored: depthExplored,
            depthLimited: depthLimited,
            hasCycle: cycle,
            evaluation: evaluation);
      });

  bool _hasCycle(
      Iterable<String> nodes, Map<String, Map<ParentRole, String>> parents) {
    final counts = {for (final node in nodes) node: 0};
    for (final edges in parents.values) {
      for (final parent in edges.values) {
        counts[parent] = counts[parent]! + 1;
      }
    }
    final pending =
        Queue<String>.of(counts.keys.where((id) => counts[id] == 0));
    var visited = 0;
    while (pending.isNotEmpty) {
      final node = pending.removeFirst();
      visited++;
      for (final parent in parents[node]?.values ?? const <String>[]) {
        final remaining = counts[parent]! - 1;
        counts[parent] = remaining;
        if (remaining == 0) pending.add(parent);
      }
    }
    return visited != counts.length;
  }
}
