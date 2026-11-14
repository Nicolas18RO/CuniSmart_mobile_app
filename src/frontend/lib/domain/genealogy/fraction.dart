class Fraction implements Comparable<Fraction> {
  const Fraction(int numerator, int denominator)
      : _numerator = numerator,
        _denominator = denominator,
        assert(denominator != 0);

  Fraction.big(BigInt numerator, BigInt denominator)
      : _numerator = numerator,
        _denominator = denominator {
    if (denominator == BigInt.zero) throw ArgumentError('Zero denominator');
  }

  final Object _numerator;
  final Object _denominator;

  BigInt get numerator =>
      _numerator is BigInt ? _numerator : BigInt.from(_numerator as int);
  BigInt get denominator =>
      _denominator is BigInt ? _denominator : BigInt.from(_denominator as int);

  Fraction operator +(Fraction other) {
    return Fraction.big(
      numerator * other.denominator + other.numerator * denominator,
      denominator * other.denominator,
    )._reduced;
  }

  Fraction operator -(Fraction other) {
    return Fraction.big(
      numerator * other.denominator - other.numerator * denominator,
      denominator * other.denominator,
    )._reduced;
  }

  Fraction operator *(Fraction other) {
    return Fraction.big(
      numerator * other.numerator,
      denominator * other.denominator,
    )._reduced;
  }

  Fraction operator /(int value) {
    return Fraction.big(numerator, denominator * BigInt.from(value))._reduced;
  }

  bool operator >=(Fraction other) => compareTo(other) >= 0;

  Fraction pow(int exponent) {
    var result = const Fraction(1, 1);
    for (var i = 0; i < exponent; i++) {
      result *= this;
    }
    return result;
  }

  Fraction get _reduced {
    var a = numerator.abs();
    var b = denominator.abs();
    while (b != BigInt.zero) {
      final next = a % b;
      a = b;
      b = next;
    }
    final sign = (numerator < BigInt.zero) ^ (denominator < BigInt.zero)
        ? -BigInt.one
        : BigInt.one;
    return Fraction.big(sign * numerator.abs() ~/ a, denominator.abs() ~/ a);
  }

  @override
  int compareTo(Fraction other) {
    final left = _reduced;
    final right = other._reduced;
    return (left.numerator * right.denominator)
        .compareTo(right.numerator * left.denominator);
  }

  @override
  bool operator ==(Object other) {
    if (other is! Fraction) return false;
    final left = _reduced;
    final right = other._reduced;
    return left.numerator == right.numerator &&
        left.denominator == right.denominator;
  }

  @override
  int get hashCode => Object.hash(_reduced.numerator, _reduced.denominator);

  String toDecimalString() {
    final reduced = _reduced;
    final sign = reduced.numerator < BigInt.zero ? '-' : '';
    final numerator = reduced.numerator.abs();
    final denominator = reduced.denominator;
    final whole = numerator ~/ denominator;
    var rem = numerator % denominator;
    if (rem == BigInt.zero) return '$sign$whole';
    final digits = <String>[];
    // Decimal API values terminate for binary genealogy fractions. For other
    // rationals refuse silent truncation rather than inventing an exact value.
    final seen = <BigInt>{};
    while (rem != BigInt.zero) {
      if (!seen.add(rem)) throw StateError('Non-terminating decimal');
      rem *= BigInt.from(10);
      digits.add('${rem ~/ denominator}');
      rem %= denominator;
    }
    return '$sign$whole.${digits.join().replaceAll(RegExp(r'0+$'), '')}';
  }
}
