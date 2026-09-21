import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/auth_token_storage.dart';
import 'package:frontend/services/device_authenticator.dart';
import 'package:frontend/viewmodels/auth_viewmodel.dart';

import 'fake_device_authenticator.dart';

/// G8.1 — contrato biométrico (TDD). No modifica producción.
///
/// Limitación de local_auth 2.3.0 (Android):
/// `ERROR_CANCELED` y el fallo genérico se mapean a `AuthResult.failure`
/// → `authenticate()` retorna `false`. `onAuthenticationFailed` no completa
/// la Future. No hay código de plataforma para “usuario canceló” vs
/// “huella rechazada”. Sí hay [auth_error.lockedOut], [auth_error.notEnrolled]
/// y `no_fragment_activity`.
void main() {
  const baseUrl = 'http://example.test';

  const identityNotVerifiedMessage =
      'No se pudo verificar tu identidad. Inténtalo nuevamente.';
  const lockoutMessage =
      'La autenticación biométrica está temporalmente bloqueada. '
      'Intenta nuevamente más tarde.';
  const platformMessage =
      'No fue posible activar la autenticación biométrica. Inténtalo nuevamente.';
  const persistenceMessage = 'No se pudo guardar la preferencia.';

  ({
    AuthViewModel vm,
    FakeDeviceAuthenticator device,
    List<http.Request> puts,
  }) harness({
    required FakeDeviceAuthenticator device,
    int putStatus = 200,
    String putBody = '{"biometric_enabled":true}',
  }) {
    final puts = <http.Request>[];
    final api = ApiClient(
      httpClient: MockClient((request) async {
        if (request.method == 'PUT') {
          puts.add(request);
          return http.Response(putBody, putStatus);
        }
        return http.Response(
          jsonEncode({'biometric_enabled': false}),
          200,
        );
      }),
      baseUrl: baseUrl,
    );
    final vm = AuthViewModel(
      authService: AuthService(
        apiClient: api,
        tokenStorage: AuthTokenStorage.inMemory(),
      ),
      deviceAuth: device,
    );
    return (vm: vm, device: device, puts: puts);
  }

  group('G8.1 hardware unavailable', () {
    test('does not prompt, does not PUT, reports unavailable', () async {
      final h = harness(
        device: FakeDeviceAuthenticator(available: false),
      );

      final ok = await h.vm.setBiometricEnabled(true);

      expect(ok, isFalse);
      expect(h.device.authenticateCalls, 0);
      expect(h.puts, isEmpty);
      expect(h.vm.biometricEnabled, isFalse);
      expect(h.vm.biometricHardwareAvailable, isFalse);
      expect(h.vm.biometricError, isNotNull);
      expect(h.vm.biometricError, isNot(persistenceMessage));
      expect(h.vm.biometricError, isNot(contains('PlatformException')));
    });
  });

  group('G8.1 hardware available + successful authenticate', () {
    test('allows activation and PUTs biometric_enabled true', () async {
      final h = harness(
        device: FakeDeviceAuthenticator(
          available: true,
          outcome: FakeBiometricAuthOutcome.success,
        ),
      );

      final ok = await h.vm.setBiometricEnabled(true);

      expect(ok, isTrue);
      expect(h.device.authenticateCalls, 1);
      expect(h.vm.biometricEnabled, isTrue);
      expect(h.vm.biometricError, isNull);
      expect(h.puts, hasLength(1));
      expect(jsonDecode(h.puts.single.body), {'biometric_enabled': true});
    });
  });

  group(
    'G8.1 authenticate() == false '
    '(local_auth Android: cancel and reject are the same result)',
    () {
      test('user cancel does not enable flag or PUT, not a technical error',
          () async {
        final h = harness(
          device: FakeDeviceAuthenticator(
            available: true,
            outcome: FakeBiometricAuthOutcome.failed,
          ),
        );

        final ok = await h.vm.setBiometricEnabled(true);

        expect(ok, isFalse);
        expect(h.device.authenticateCalls, 1);
        expect(h.puts, isEmpty);
        expect(h.vm.biometricEnabled, isFalse);
        expect(h.vm.biometricError, identityNotVerifiedMessage);
        expect(h.vm.biometricError, isNot(persistenceMessage));
        expect(h.vm.biometricError, isNot(contains('PlatformException')));
      });

      test('rejected authentication does not enable flag or PUT', () async {
        final h = harness(
          device: FakeDeviceAuthenticator(
            available: true,
            outcome: FakeBiometricAuthOutcome.failed,
          ),
        );

        final ok = await h.vm.setBiometricEnabled(true);

        expect(ok, isFalse);
        expect(h.puts, isEmpty);
        expect(h.vm.biometricEnabled, isFalse);
        expect(h.vm.biometricError, identityNotVerifiedMessage);
        expect(h.vm.biometricError, isNot(platformMessage));
      });
    },
  );

  group('G8.1 PlatformException', () {
    test('is classified, not swallowed as false, without technical text',
        () async {
      final h = harness(
        device: FakeDeviceAuthenticator(
          available: true,
          outcome: FakeBiometricAuthOutcome.platformError,
        ),
      );

      final ok = await h.vm.setBiometricEnabled(true);

      expect(ok, isFalse);
      expect(h.device.authenticateCalls, 1);
      expect(h.puts, isEmpty);
      expect(h.vm.biometricEnabled, isFalse);
      expect(h.vm.biometricError, platformMessage);
      expect(h.vm.biometricError, isNot(contains('no_fragment_activity')));
      expect(h.vm.biometricError, isNot(contains('FragmentActivity')));
      expect(h.vm.biometricError, isNot(contains('PlatformException')));
      expect(h.vm.biometricError, isNot(persistenceMessage));
      expect(h.vm.biometricError, isNot(identityNotVerifiedMessage));
    });
  });

  group('G8.1 lockout', () {
    test('LockedOut PlatformException is a distinct user-facing state',
        () async {
      final h = harness(
        device: FakeDeviceAuthenticator(
          available: true,
          outcome: FakeBiometricAuthOutcome.lockedOut,
        ),
      );

      final ok = await h.vm.setBiometricEnabled(true);

      expect(ok, isFalse);
      expect(h.puts, isEmpty);
      expect(h.vm.biometricEnabled, isFalse);
      expect(h.vm.biometricError, lockoutMessage);
      expect(h.vm.biometricError, isNot(contains(auth_error.lockedOut)));
      expect(h.vm.biometricError, isNot(persistenceMessage));
      expect(h.vm.biometricError, isNot(identityNotVerifiedMessage));
    });
  });

  group('G8.1 backend fails after local success', () {
    test('does not retry biometrics, does not mark enabled, persistence error',
        () async {
      final h = harness(
        device: FakeDeviceAuthenticator(
          available: true,
          outcome: FakeBiometricAuthOutcome.success,
        ),
        putStatus: 500,
        putBody: '{"detail":"Internal server error"}',
      );

      final ok = await h.vm.setBiometricEnabled(true);

      expect(ok, isFalse);
      expect(h.device.authenticateCalls, 1);
      expect(h.puts, hasLength(1));
      expect(h.vm.biometricEnabled, isFalse);
      expect(h.vm.biometricError, persistenceMessage);
    });
  });

  group('G8.1 deactivation', () {
    test('does not prompt and PUTs biometric_enabled false', () async {
      final h = harness(
        device: FakeDeviceAuthenticator(
          available: true,
          outcome: FakeBiometricAuthOutcome.success,
        ),
        putBody: '{"biometric_enabled":false}',
      );

      final ok = await h.vm.setBiometricEnabled(false);

      expect(ok, isTrue);
      expect(h.device.authenticateCalls, 0);
      expect(h.vm.biometricEnabled, isFalse);
      expect(h.vm.biometricError, isNull);
      expect(h.puts, hasLength(1));
      expect(jsonDecode(h.puts.single.body), {'biometric_enabled': false});
    });
  });

  group('G8.1 LocalDeviceAuthenticator must not swallow PlatformException', () {
    test('no_fragment_activity is not converted to silent false', () async {
      final plugin = _ScriptedLocalAuth(
        onAuthenticate: () => throw PlatformException(
          code: 'no_fragment_activity',
          message:
              'local_auth plugin requires activity to be a FragmentActivity.',
        ),
      );
      final authenticator = LocalDeviceAuthenticator(plugin: plugin);

      await expectLater(
        authenticator.authenticate(reason: 'activar'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'no_fragment_activity',
          ),
        ),
      );
    });

    test('LockedOut is not converted to silent false', () async {
      final plugin = _ScriptedLocalAuth(
        onAuthenticate: () => throw PlatformException(
          code: auth_error.lockedOut,
          message: 'The API is locked out due to too many attempts.',
        ),
      );
      final authenticator = LocalDeviceAuthenticator(plugin: plugin);

      await expectLater(
        authenticator.authenticate(reason: 'activar'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            auth_error.lockedOut,
          ),
        ),
      );
    });
  });
}

class _ScriptedLocalAuth extends Fake implements LocalAuthentication {
  _ScriptedLocalAuth({required this.onAuthenticate});

  final Future<bool> Function() onAuthenticate;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #authenticate) {
      return onAuthenticate();
    }
    return super.noSuchMethod(invocation);
  }
}
