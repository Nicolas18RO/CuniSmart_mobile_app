import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/r3/application/r3_use_cases.dart';
import 'package:frontend/features/r3/domain/r3_models.dart';
import 'package:frontend/features/r3/domain/r3_repository.dart';
import 'package:frontend/models/rabbit.dart';
import 'package:frontend/voice/engine/r3_voice_facade.dart';

class _Repo implements R3Repository {
  @override
  Future<Pedigree> pedigree(String uuid) async => Pedigree(
        father: const PedigreeAnimal(
            uuid: 'f',
            name: 'Papá',
            sex: 'male',
            generation: 1,
            deleted: false),
        mother: const PedigreeAnimal(
            uuid: 'm',
            name: 'Mamá',
            sex: 'female',
            generation: 1,
            deleted: false),
        ancestors: const [],
        descendants: const [
          PedigreeAnimal(
              uuid: 'c',
              name: 'Hijo',
              sex: 'male',
              generation: -1,
              deleted: false),
          PedigreeAnimal(
              uuid: 'n',
              name: 'Nieto',
              sex: 'male',
              generation: -2,
              deleted: false)
        ],
        integrity: 'VALID',
        integrityIssues: const [],
        links: const [],
      );
  @override
  Future<KinshipEvaluation> kinship(
          {required String firstUuid,
          required String secondUuid,
          String mode = 'relationship'}) async =>
      const KinshipEvaluation(
          status: 'CALCULABLE',
          relationshipCoefficient: '0.25',
          expectedInbreeding: '0.125',
          riskLevel: 'HIGH',
          relationshipType: 'full_siblings',
          commonAncestors: const [
            KinshipAncestor(
                uuid: 'a', n1: 1, n2: 1, contribution: '0.25', name: 'Ancestro')
          ],
          reason: null,
          isExact: true);
  @override
  Future<List<ReproductiveEvent>> events() async => const [];
  @override
  Future<List<ReproductiveEvent>> calendar(
          {required String startDate, required String endDate}) async =>
      const [];
  @override
  Future<void> setParent(
      {required String childUuid,
      required String role,
      required String parentUuid,
      int? version}) async {}
  @override
  Future<void> clearParent(
      {required String childUuid,
      required String role,
      required int version}) async {}
  @override
  Future<ReproductiveEvent> event(String uuid) => throw UnimplementedError();
  @override
  Future<ReproductiveEvent> createEvent(
          {required String maleUuid,
          required String femaleUuid,
          required String matingDate,
          String notes = ''}) =>
      throw UnimplementedError();
  @override
  Future<ReproductiveEvent> updateEvent(
          {required String uuid,
          required int version,
          String? matingDate,
          String? notes}) =>
      throw UnimplementedError();
  @override
  Future<void> deleteEvent({required String uuid, required int version}) =>
      throw UnimplementedError();
}

Rabbit _rabbit(String uuid, String name) => Rabbit(
    id: 1,
    uuid: uuid,
    name: name,
    breed: 'Raza',
    sex: 'male',
    birthDate: '2025-01-01',
    status: 'active',
    notes: '',
    version: 1,
    createdAt: '',
    updatedAt: '');

void main() {
  final facade = R3VoiceFacade(R3UseCases(_Repo()));
  final rabbits = [_rabbit('p', 'Pepe'), _rabbit('l', 'Luna')];

  test('responde padres con datos del pedigree', () async {
    expect(await facade.answer('¿Quiénes son los padres de Pepe?', rabbits),
        contains('Papá y Mamá'));
  });
  test('responde parentesco con riesgo y exactitud', () async {
    final answer =
        await facade.answer('¿Pepe se puede cruzar con Luna?', rabbits);
    expect(answer, contains('riesgo alto'));
    expect(answer, contains('exacto'));
  });
  test('acepta formulaciones naturales de parentesco y padre', () async {
    expect(await facade.answer('¿Quién es el papá de Pepe?', rabbits),
        contains('Papá'));
    expect(await facade.answer('¿Qué parentesco tienen Pepe y Luna?', rabbits),
        contains('hermanos completos'));
    expect(await facade.answer('¿Son familiares Pepe y Luna?', rabbits),
        contains('Sí.'));
  });
  test('distingue hijos directos de descendientes', () async {
    expect(await facade.answer('¿Cuántos hijos tiene Pepe?', rabbits),
        contains('un hijo registrado'));
    expect(
        await facade.answer('¿Quiénes son los descendientes de Pepe?', rabbits),
        contains('dos descendientes'));
    expect(await facade.answer('Pepe tiene descendientes', rabbits),
        contains('Sí, Pepe tiene'));
  });
  test('pide nombre completo si es ambiguo o desconocido', () async {
    expect(await facade.answer('¿Quiénes son los padres de Nadie?', rabbits),
        contains('No encontré'));
  });
  test('ignora órdenes fuera del alcance R3', () async {
    expect(await facade.answer('crear conejo', rabbits), isNull);
  });
}
