import 'package:frontend/core/errors/api_exception.dart';
import 'package:frontend/features/r3/domain/r3_models.dart';
import 'package:frontend/features/r3/domain/r3_repository.dart';

class FakeR3Repository implements R3Repository {
  Pedigree pedigreeValue = const Pedigree(
    ancestors: [],
    descendants: [],
    integrity: 'VALID',
    integrityIssues: [],
    links: [],
  );
  KinshipEvaluation kinshipValue = const KinshipEvaluation(
    status: 'NO_CALCULABLE',
    relationshipCoefficient: null,
    expectedInbreeding: null,
    riskLevel: 'NO_CALCULABLE',
    commonAncestors: [],
    reason: 'INFORMACIÓN_GENEALÓGICA_INSUFICIENTE',
  );
  List<ReproductiveEvent> eventValues = [];
  Object? error;

  void failIfNeeded() {
    if (error != null) throw error!;
  }

  @override
  Future<Pedigree> pedigree(String rabbitUuid) async {
    failIfNeeded();
    return pedigreeValue;
  }

  @override
  Future<void> setParent(
          {required String childUuid,
          required String role,
          required String parentUuid,
          int? version}) async =>
      failIfNeeded();
  @override
  Future<void> clearParent(
          {required String childUuid,
          required String role,
          required int version}) async =>
      failIfNeeded();
  @override
  Future<KinshipEvaluation> kinship(
      {required String firstUuid,
      required String secondUuid,
      String mode = 'relationship'}) async {
    failIfNeeded();
    return kinshipValue;
  }

  @override
  Future<List<ReproductiveEvent>> events() async {
    failIfNeeded();
    return eventValues;
  }

  @override
  Future<ReproductiveEvent> event(String uuid) async {
    failIfNeeded();
    return eventValues.firstWhere((e) => e.uuid == uuid);
  }

  @override
  Future<ReproductiveEvent> createEvent(
      {required String maleUuid,
      required String femaleUuid,
      required String matingDate,
      String notes = ''}) async {
    failIfNeeded();
    return eventValues.first;
  }

  @override
  Future<ReproductiveEvent> updateEvent(
      {required String uuid,
      required int version,
      String? matingDate,
      String? notes}) async {
    failIfNeeded();
    return eventValues.first;
  }

  @override
  Future<void> deleteEvent(
          {required String uuid, required int version}) async =>
      failIfNeeded();
  @override
  Future<List<ReproductiveEvent>> calendar(
      {required String startDate, required String endDate}) async {
    failIfNeeded();
    return eventValues;
  }

  void conflict() => error = ApiException(
        '{"detail":"conflicto","code":"version_conflict"}',
        statusCode: 409,
      );
}
