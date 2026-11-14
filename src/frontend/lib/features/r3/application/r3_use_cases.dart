import '../domain/r3_models.dart';
import '../domain/r3_repository.dart';
import '../domain/r3_local_results.dart';

class R3UseCases {
  const R3UseCases(this.repository);
  final R3Repository repository;

  Future<Pedigree> loadPedigree(String uuid) => repository.pedigree(uuid);
  Future<void> assignParent(
          {required String child,
          required String role,
          required String parent,
          int? version}) =>
      repository.setParent(
          childUuid: child, role: role, parentUuid: parent, version: version);
  Future<void> removeParent(
          {required String child,
          required String role,
          required int version}) =>
      repository.clearParent(childUuid: child, role: role, version: version);
  Future<KinshipEvaluation> evaluate(String a, String b,
          {String mode = 'relationship'}) =>
      repository.kinship(firstUuid: a, secondUuid: b, mode: mode);
  Future<List<ReproductiveEvent>> loadEvents({
    String? participant,
    ReproductiveRole? role,
    String? from,
    String? to,
    bool includeDeleted = false,
  }) {
    final source = repository;
    if (source is R3ReproductiveHistory) {
      return (source as R3ReproductiveHistory).history(
          participantUuid: participant,
          role: role,
          from: from,
          to: to,
          includeDeleted: includeDeleted);
    }
    return source.events();
  }

  Future<ReproductiveEvent> createEvent(
          {required String male,
          required String female,
          required String date,
          String notes = ''}) =>
      repository.createEvent(
          maleUuid: male, femaleUuid: female, matingDate: date, notes: notes);
  Future<ReproductiveEvent> updateEvent(
          {required ReproductiveEvent event, String? date, String? notes}) =>
      repository.updateEvent(
          uuid: event.uuid,
          version: event.version,
          matingDate: date,
          notes: notes);
  Future<void> deleteEvent(ReproductiveEvent event) =>
      repository.deleteEvent(uuid: event.uuid, version: event.version);
  Future<List<ReproductiveEvent>> loadCalendar(String start, String end) =>
      repository.calendar(startDate: start, endDate: end);
}
