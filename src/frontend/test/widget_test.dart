import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/viewmodels/auth_viewmodel.dart';

void main() {
  test('AuthGate values used by R1 session machine', () {
    expect(
      AuthGate.values,
      containsAll([
        AuthGate.splash,
        AuthGate.login,
        AuthGate.biometricLock,
        AuthGate.app,
      ]),
    );
  });
}
