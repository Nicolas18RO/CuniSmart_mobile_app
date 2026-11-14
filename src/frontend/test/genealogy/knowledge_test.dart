import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/domain/genealogy/kinship.dart';
import 'package:frontend/domain/genealogy/fraction.dart';

void main() {
  test('dense path budget is explicit and never a zero result', () {
    final herd = <String, KinshipAnimal>{
      '0': const KinshipAnimal(uuid: '0', knowledge: 'FOUNDER'),
      '1': const KinshipAnimal(uuid: '1', knowledge: 'FOUNDER'),
    };
    var left = '0';
    var right = '1';
    for (var i = 0; i < 10; i++) {
      final a = '${2 * i + 2}';
      final b = '${2 * i + 3}';
      herd[a] = KinshipAnimal(
          uuid: a, father: left, mother: right, knowledge: 'RECORDED');
      herd[b] = KinshipAnimal(
          uuid: b, father: left, mother: right, knowledge: 'RECORDED');
      left = a;
      right = b;
    }
    final result = evaluateKinship(left, right, herd);
    expect(result.status, 'NO_CALCULABLE');
    expect(result.relationship, isNull);
    expect(result.reason, genealogyLimitReason);
  });
  test('unrecorded parents do not declare founders', () {
    final result = evaluateKinship('a', 'b', {
      'a': const KinshipAnimal(uuid: 'a'),
      'b': const KinshipAnimal(uuid: 'b'),
    });
    expect(result.status, 'NO_CALCULABLE');
    expect(result.relationship, isNull);
    expect(result.expectedInbreeding, isNull);
    expect(result.riskLevel, 'NO_CALCULABLE');
  });

  test('explicit independent founders are calculable', () {
    final result = evaluateKinship('a', 'b', {
      'a': const KinshipAnimal(uuid: 'a', knowledge: 'FOUNDER'),
      'b': const KinshipAnimal(uuid: 'b', knowledge: 'FOUNDER'),
    });
    expect(result.status, 'CALCULABLE');
    expect(result.relationship?.toDecimalString(), '0');
  });

  test('unknown father-daughter remains a known partial relationship', () {
    final result = evaluateKinship('pepe', 'monica', {
      'pepe': const KinshipAnimal(uuid: 'pepe', name: 'Pepe', sex: 'male'),
      'lupe': const KinshipAnimal(uuid: 'lupe', name: 'Lupe', sex: 'female'),
      'monica': const KinshipAnimal(
        uuid: 'monica',
        name: 'Mónica',
        sex: 'female',
        father: 'pepe',
        mother: 'lupe',
        knowledge: 'RECORDED',
      ),
    });
    expect(result.status, 'PARTIAL');
    expect(result.relationship, const Fraction(1, 2));
    expect(result.expectedInbreeding, isNull);
    expect(result.minimumKnownInbreeding, const Fraction(1, 4));
    expect(result.relationshipType, 'FATHER_DAUGHTER');
    expect(result.riskLevel, 'ALTO');
    expect(result.isExact, isFalse);
    expect(result.commonAncestors.single.name, 'Pepe');
  });

  test('unknown branch cannot produce a zero coefficient', () {
    final result = evaluateKinship('a', 'b', {
      'a': const KinshipAnimal(
        uuid: 'a',
        father: 'p',
        mother: 'q',
        knowledge: 'RECORDED',
      ),
      'p': const KinshipAnimal(uuid: 'p', knowledge: 'FOUNDER'),
      'q': const KinshipAnimal(uuid: 'q'),
      'b': const KinshipAnimal(uuid: 'b', knowledge: 'FOUNDER'),
    });
    expect(result.status, 'NO_CALCULABLE');
    expect(result.expectedInbreeding, isNull);
  });
}
