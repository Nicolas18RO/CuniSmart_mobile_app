import '../../../core/errors/api_exception.dart';
import '../../../data/local/app_database.dart';
import '../../../domain/genealogy/parent_link.dart';
import '../../../services/auth_service.dart';
import '../application/r3_local_persistence.dart';
import '../domain/r3_local_results.dart';
import '../domain/r3_models.dart';
import '../domain/r3_repository.dart';
import 'local_r3_queries.dart';

/// Adapts the account-scoped local facts to the existing R3 use cases.
class LocalR3Repository implements R3Repository, R3ReproductiveHistory {
  LocalR3Repository(this.database, this.auth,
      {DateTime Function()? clock, this.onLocalMutation})
      : _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final AuthService auth;
  final void Function()? onLocalMutation;
  final DateTime Function() _clock;

  LocalR3Queries get _queries => LocalR3Queries.forSession(database, auth);
  R3LocalPersistence get _writes =>
      R3LocalPersistence.forSession(database, auth);

  Future<T> _guard<T>(Future<T> Function() action) async {
    final generation = auth.generation;
    final result = await action();
    if (generation != auth.generation ||
        !auth.localDataUnlocked ||
        !await auth.canAccessLocally() ||
        generation != auth.generation ||
        !auth.localDataUnlocked) {
      throw ApiException('La sesión cambió', code: 'session_changed');
    }
    return result;
  }

  @override
  Future<Pedigree> pedigree(String rabbitUuid) => _guard(() async {
        final queries = _queries;
        final up = await queries.genealogy([rabbitUuid], includeDeleted: true);
        final down = await queries.genealogy([rabbitUuid], descendants: true);
        final direct =
            up.links.where((item) => item.link.childUuid == rabbitUuid);
        PedigreeAnimal? parent(ParentRole role) {
          for (final item in direct) {
            if (item.link.role == role) return _animal(item.parent, 1);
          }
          return null;
        }

        final father = parent(ParentRole.father);
        final mother = parent(ParentRole.mother);
        IndividualInbreeding? individual;
        if (father != null &&
            mother != null &&
            !up.hasCycle &&
            up.coverage != GenealogyCoverage.inconsistent) {
          final result =
              (await queries.genealogy([father.uuid, mother.uuid])).evaluation!;
          individual = IndividualInbreeding(
            status: result.status,
            coefficient: result.expectedInbreeding?.toDecimalString(),
            minimumKnownCoefficient:
                result.minimumKnownInbreeding?.toDecimalString(),
            isExact: result.isExact,
            riskLevel: result.riskLevel,
            warnings: result.warnings,
          );
        }
        return Pedigree(
          father: father,
          mother: mother,
          ancestors: _nodes(up, rabbitUuid),
          descendants: _nodes(down, rabbitUuid, descendants: true),
          integrity: up.hasCycle ||
                  down.hasCycle ||
                  up.coverage == GenealogyCoverage.inconsistent
              ? 'INCONSISTENT'
              : 'VALID',
          integrityIssues: [
            if (up.hasCycle || down.hasCycle) 'Ciclo detectado'
          ],
          individualInbreeding: individual,
          local: up,
          links: [
            for (final item in up.links)
              PedigreeLink(
                  role: item.link.role.storageValue,
                  version: item.link.version,
                  childUuid: item.link.childUuid)
          ],
        );
      });

  List<PedigreeAnimal> _nodes(LocalGenealogy graph, String root,
      {bool descendants = false}) {
    final edges = <String, List<String>>{};
    for (final relation in graph.links) {
      final link = relation.link;
      final from = descendants ? link.parentUuid : link.childUuid;
      final to = descendants ? link.childUuid : link.parentUuid;
      edges.putIfAbsent(from, () => []).add(to);
    }
    final levels = {root: 0};
    final queue = [root];
    for (var i = 0; i < queue.length; i++) {
      for (final next in edges[queue[i]] ?? const <String>[]) {
        if (levels.containsKey(next)) continue;
        levels[next] = levels[queue[i]]! + 1;
        queue.add(next);
      }
    }
    return [
      for (final uuid in queue.skip(1))
        _animal(graph.nodes[uuid]!, levels[uuid]! * (descendants ? -1 : 1)),
    ];
  }

  PedigreeAnimal _animal(LocalRabbitReference ref, int generation) {
    final rabbit = ref.rabbit;
    return PedigreeAnimal(
        uuid: ref.uuid,
        name: _name(ref),
        sex: rabbit?.sex ?? '',
        generation: generation,
        deleted: rabbit?.deletedAt != null,
        genealogyKnowledge: rabbit?.genealogyKnowledge ?? 'UNKNOWN');
  }

  String _name(LocalRabbitReference ref) => switch (ref.availability) {
        LocalRabbitAvailability.unavailable =>
          'Ficha local no disponible (${ref.uuid})',
        LocalRabbitAvailability.deleted => '${ref.rabbit!.name} (eliminado)',
        LocalRabbitAvailability.pendingCreate =>
          '${ref.rabbit!.name} (alta pendiente)',
        LocalRabbitAvailability.available => ref.rabbit!.name,
      };

  @override
  Future<KinshipEvaluation> kinship(
          {required String firstUuid,
          required String secondUuid,
          String mode = 'relationship'}) =>
      _guard(() async {
        final graph = await _queries.genealogy([firstUuid, secondUuid]);
        return KinshipEvaluation.fromJson(graph.evaluation!.toPayload(),
            local: graph);
      });

  ParentRole _role(String value) =>
      ParentRole.fromStorage(value) ??
      (throw ApiException('Rol de progenitor inválido'));

  @override
  Future<void> setParent(
          {required String childUuid,
          required String role,
          required String parentUuid,
          int? version}) =>
      _guard(() async {
        await _writes.assignParent(
            childUuid: childUuid,
            parentUuid: parentUuid,
            role: _role(role),
            version: version);
        onLocalMutation?.call();
      });

  @override
  Future<void> clearParent(
          {required String childUuid,
          required String role,
          required int version}) =>
      _guard(() async {
        await _writes.clearParent(
            childUuid: childUuid, role: _role(role), version: version);
        onLocalMutation?.call();
      });

  String _today() => _clock().toIso8601String().split('T').first;

  Future<ReproductiveEvent> _record(
      LocalR3Queries queries, LocalReproductiveRecord row,
      {required String today}) async {
    final graph = await queries.genealogy([row.male.uuid, row.female.uuid]);
    final days = DateTime.parse('${row.estimatedBirthDate}T00:00:00Z')
        .difference(DateTime.parse('${today}T00:00:00Z'))
        .inDays;
    return ReproductiveEvent(
      uuid: row.uuid,
      maleUuid: row.male.uuid,
      maleName: _name(row.male),
      femaleUuid: row.female.uuid,
      femaleName: _name(row.female),
      matingDate: row.matingDate,
      estimatedBirthDate: row.estimatedBirthDate,
      notes: row.notes,
      version: row.version,
      calendarState: LocalCalendarEntry(row, days).calendarState,
      daysRemaining: days,
      kinship: KinshipEvaluation.fromJson(graph.evaluation!.toPayload(),
          local: graph),
      local: row,
    );
  }

  @override
  Future<List<ReproductiveEvent>> history(
          {String? participantUuid,
          ReproductiveRole? role,
          String? from,
          String? to,
          bool includeDeleted = false}) =>
      _guard(() async {
        final queries = _queries;
        final today = _today();
        final rows = await queries.events(
            participantUuid: participantUuid,
            role: role,
            from: from,
            to: to,
            includeDeleted: includeDeleted);
        return [
          for (final row in rows) await _record(queries, row, today: today)
        ];
      });

  @override
  Future<List<ReproductiveEvent>> events() => history();

  @override
  Future<ReproductiveEvent> event(String uuid) => _guard(() async {
        final queries = _queries;
        final row = await queries.event(uuid);
        if (row == null) {
          throw ApiException('Evento no disponible en la copia local');
        }
        return _record(queries, row, today: _today());
      });

  @override
  Future<ReproductiveEvent> createEvent(
          {required String maleUuid,
          required String femaleUuid,
          required String matingDate,
          String notes = ''}) =>
      _guard(() async {
        final row = await _writes.createEvent(
            maleUuid: maleUuid,
            femaleUuid: femaleUuid,
            matingDate: matingDate,
            notes: notes);
        onLocalMutation?.call();
        return event(row.uuid);
      });

  @override
  Future<ReproductiveEvent> updateEvent(
          {required String uuid,
          required int version,
          String? matingDate,
          String? notes}) =>
      _guard(() async {
        await _writes.updateEvent(
            uuid: uuid, version: version, matingDate: matingDate, notes: notes);
        onLocalMutation?.call();
        return event(uuid);
      });

  @override
  Future<void> deleteEvent({required String uuid, required int version}) =>
      _guard(() async {
        await _writes.deleteEvent(uuid: uuid, version: version);
        onLocalMutation?.call();
      });

  @override
  Future<List<ReproductiveEvent>> calendar(
          {required String startDate, required String endDate}) =>
      _guard(() async {
        final queries = _queries;
        final today = _today();
        final rows = await queries.calendar(startDate, endDate, today: today);
        return [
          for (final row in rows)
            await _record(queries, row.event, today: today)
        ];
      });
}
