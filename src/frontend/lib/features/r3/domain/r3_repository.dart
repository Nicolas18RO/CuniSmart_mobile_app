import 'r3_models.dart';
import 'r3_local_results.dart';

abstract interface class R3ReproductiveHistory {
  Future<List<ReproductiveEvent>> history({
    String? participantUuid,
    ReproductiveRole? role,
    String? from,
    String? to,
    bool includeDeleted = false,
  });
}

abstract interface class R3Repository {
  Future<Pedigree> pedigree(String rabbitUuid);
  Future<void> setParent(
      {required String childUuid,
      required String role,
      required String parentUuid,
      int? version});
  Future<void> clearParent(
      {required String childUuid, required String role, required int version});
  Future<KinshipEvaluation> kinship(
      {required String firstUuid, required String secondUuid, String mode});
  Future<List<ReproductiveEvent>> events();
  Future<ReproductiveEvent> event(String uuid);
  Future<ReproductiveEvent> createEvent(
      {required String maleUuid,
      required String femaleUuid,
      required String matingDate,
      String notes});
  Future<ReproductiveEvent> updateEvent(
      {required String uuid,
      required int version,
      String? matingDate,
      String? notes});
  Future<void> deleteEvent({required String uuid, required int version});
  Future<List<ReproductiveEvent>> calendar(
      {required String startDate, required String endDate});
}
