import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/domain/genealogy/kinship.dart';
import 'package:frontend/domain/genealogy/fraction.dart';

void main() {
  test('1350 exact comparisons against the shared independent matrix', () {
    final data = jsonDecode(
        File('../backend/core/fixtures/r3_relationship_matrix.json')
            .readAsStringSync()) as Map<String, dynamic>;
    var count = 0;
    for (final graph in data['graphs'] as List) {
      final rows = graph['parents'] as List;
      final herd = <String, KinshipAnimal>{};
      for (var i = 0; i < rows.length; i++) {
        final p = rows[i][0];
        final q = rows[i][1];
        herd['$i'] = KinshipAnimal(
            uuid: '$i',
            father: p == null ? null : '$p',
            mother: q == null ? null : '$q',
            knowledge: p == null ? 'FOUNDER' : 'RECORDED');
      }
      for (final row in graph['expected'] as List) {
        final result =
            evaluateKinship(row[0] as String, row[1] as String, herd);
        final expected = Fraction.big(
            BigInt.parse(row[2] as String), BigInt.parse(row[3] as String));
        expect(result.status, 'CALCULABLE');
        expect(result.relationship, expected);
        expect(result.expectedInbreeding, expected / 2);
        expect(
            result.riskLevel,
            (expected / 2) >= highThreshold
                ? 'ALTO'
                : (expected / 2) >= preventiveThreshold
                    ? 'PREVENTIVO'
                    : 'SIN_ADVERTENCIA');
        count++;
      }
    }
    expect(count, 1350);
  });
}
