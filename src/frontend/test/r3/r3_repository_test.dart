import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/r3/data/remote_r3_repository.dart';

void main() {
  test('maps pedigree and preserves unknown parents', () async {
    final repo = RemoteR3Repository(ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async => http.Response(
          jsonEncode({
            'father': null,
            'mother': null,
            'ancestors': [],
            'descendants': [],
            'integrity': 'VALID',
            'integrityIssues': [],
          }),
          200)),
    ));
    final pedigree = await repo.pedigree('child');
    expect(pedigree.father, isNull);
    expect(pedigree.mother, isNull);
    expect(pedigree.ancestors, isEmpty);
  });

  test('maps NO_CALCULABLE without inventing zero', () async {
    final repo = RemoteR3Repository(ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async => http.Response(
          jsonEncode({
            'status': 'NO_CALCULABLE',
            'relationshipCoefficient': null,
            'expectedInbreeding': null,
            'riskLevel': 'NO_CALCULABLE',
            'commonAncestors': [],
            'reason': 'INFORMACIÓN_GENEALÓGICA_INSUFICIENTE',
          }),
          200)),
    ));
    final value = await repo.kinship(firstUuid: 'a', secondUuid: 'b');
    expect(value.calculable, isFalse);
    expect(value.expectedInbreeding, isNull);
  });

  test('maps partial father-daughter as minimum known risk', () async {
    final repo = RemoteR3Repository(ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async => http.Response(
          jsonEncode({
            'status': 'PARTIAL',
            'relationshipCoefficient': '0.5',
            'expectedInbreeding': null,
            'minimumKnownInbreeding': '0.25',
            'isExact': false,
            'relationshipType': 'FATHER_DAUGHTER',
            'riskLevel': 'ALTO',
            'commonAncestors': [
              {
                'uuid': 'pepe',
                'name': 'Pepe',
                'n1': 0,
                'n2': 1,
                'contribution': '0.5'
              }
            ],
            'reason': 'INFORMACIÓN_GENEALÓGICA_INSUFICIENTE',
            'warnings': ['INCOMPLETE_GENEALOGY', 'MINIMUM_KNOWN_ONLY'],
            'unknownBranches': ['pepe', 'lupe'],
          }),
          200)),
    ));
    final value = await repo.kinship(firstUuid: 'pepe', secondUuid: 'monica');
    expect(value.status, 'PARTIAL');
    expect(value.relationshipType, 'FATHER_DAUGHTER');
    expect(value.minimumKnownInbreeding, '0.25');
    expect(value.commonAncestors.single.name, 'Pepe');
    expect(value.hasKnownMinimum, isTrue);
  });

  test('maps declared-founder assumption for an exact zero', () async {
    final repo = RemoteR3Repository(ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async => http.Response(
          jsonEncode({
            'status': 'CALCULABLE',
            'relationshipCoefficient': '0',
            'expectedInbreeding': '0',
            'minimumKnownInbreeding': '0',
            'isExact': true,
            'relationshipType': 'UNRELATED',
            'riskLevel': 'SIN_ADVERTENCIA',
            'commonAncestors': [],
            'reason': null,
            'independenceAssumptionApplied': true,
            'declaredFounders': ['Lupe', 'Pepe'],
          }),
          200)),
    ));
    final value = await repo.kinship(firstUuid: 'pepe', secondUuid: 'lupe');
    expect(value.independenceAssumptionApplied, isTrue);
    expect(value.declaredFounders, ['Lupe', 'Pepe']);
    expect(value.expectedInbreeding, '0');
  });

  test('PATCH and DELETE send event version', () async {
    final requests = <http.Request>[];
    final event = {
      'uuid': 'e',
      'male_uuid': 'm',
      'male_name': 'M',
      'female_uuid': 'f',
      'female_name': 'F',
      'mating_date': '2026-10-01',
      'estimated_birth_date': '2026-11-01',
      'notes': '',
      'version': 3,
      'calendar_state': 'UPCOMING',
      'days_remaining': 1,
      'kinship_evaluation': {
        'status': 'NO_CALCULABLE',
        'relationshipCoefficient': null,
        'expectedInbreeding': null,
        'riskLevel': 'NO_CALCULABLE',
        'commonAncestors': [],
        'reason': 'insuficiente',
      },
    };
    final repo = RemoteR3Repository(ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
            request.method == 'DELETE'
                ? ''
                : jsonEncode({...event, 'version': 4}),
            request.method == 'DELETE' ? 204 : 200);
      }),
    ));
    await repo.updateEvent(uuid: 'e', version: 3, notes: 'nueva');
    await repo.deleteEvent(uuid: 'e', version: 4);
    expect(requests.map((r) => r.method), ['PATCH', 'DELETE']);
    expect(jsonDecode(requests.first.body)['version'], 3);
    expect(jsonDecode(requests.last.body)['version'], 4);
  });
}
