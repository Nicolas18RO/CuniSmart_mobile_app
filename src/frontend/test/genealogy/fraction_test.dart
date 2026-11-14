import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/domain/genealogy/fraction.dart';

void main() {
  test('large intermediates stay exact', () {
    final n = BigInt.one << 200;
    final value = Fraction.big(n + BigInt.one, n);
    expect((value * Fraction.big(n, n + BigInt.one)), const Fraction(1, 1));
    expect(value + const Fraction(1, 1),
        Fraction.big(n * BigInt.two + BigInt.one, n));
    expect(value / 2, Fraction.big(n + BigInt.one, n * BigInt.two));
    expect(value.compareTo(const Fraction(1, 1)), greaterThan(0));
  });

  test('deep binary decimal is exact and not truncated', () {
    final value = Fraction.big(BigInt.one, BigInt.one << 100);
    expect(value.toDecimalString(),
        '0.0000000000000000000000000000007888609052210118054117285652827862296732064351090230047702789306640625');
  });

  test('normalization and repeating decimal contract', () {
    expect(const Fraction(1, -2).compareTo(const Fraction(1, 2)), lessThan(0));
    expect(Fraction.big(-BigInt.two, -BigInt.from(4)), const Fraction(1, 2));
    expect(() => const Fraction(1, 3).toDecimalString(), throwsStateError);
    expect(() => Fraction.big(BigInt.one, BigInt.zero), throwsArgumentError);
  });
}
