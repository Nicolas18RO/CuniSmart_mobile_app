import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/auth/presentation/screens/login_screen.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/auth_token_storage.dart';
import 'package:frontend/services/device_credential_contract.dart';
import 'package:frontend/viewmodels/auth_viewmodel.dart';

import 'fake_device_authenticator.dart';
import 'fake_device_credential_signer.dart';

/// G10.2/G10.3 — contrato de login biométrico (opción C).
const _baseUrl = 'http://example.test';

void main() {
  AuthService buildService(
    MockClient mock, {
    AuthTokenStorage? storage,
  }) {
    return AuthService(
      apiClient: ApiClient(httpClient: mock, baseUrl: _baseUrl),
      tokenStorage: storage ?? AuthTokenStorage.inMemory(),
    );
  }

  ({
    AuthViewModel vm,
    FakeDeviceAuthenticator device,
    AuthTokenStorage storage,
    List<http.Request> requests,
  }) harness({
    FakeDeviceAuthenticator? device,
    AuthTokenStorage? storage,
    int Function(http.Request request)? statusFor,
    Map<String, dynamic> Function(http.Request request)? bodyFor,
  }) {
    final captured = <http.Request>[];
    final tokenStorage = storage ?? AuthTokenStorage.inMemory();
    final fake = device ??
        FakeDeviceAuthenticator(
          available: true,
          outcome: FakeBiometricAuthOutcome.success,
        );
    final api = ApiClient(
      httpClient: MockClient((request) async {
        captured.add(request);
        if (statusFor != null) {
          final code = statusFor(request);
          final payload = bodyFor?.call(request) ?? <String, dynamic>{};
          return http.Response(jsonEncode(payload), code);
        }
        if (request.url.path == '/api/auth/login/') {
          return http.Response(
            jsonEncode({'access': 'a', 'refresh': 'r'}),
            200,
          );
        }
        if (request.url.path == '/api/auth/logout/') {
          return http.Response('', 204);
        }
        if (request.url.path == '/api/auth/device-credentials/') {
          return http.Response(
            jsonEncode({
              'id': 'cred-1',
              'created_at': '2026-09-20T00:00:00Z',
            }),
            201,
          );
        }
        if (request.url.path == '/api/auth/device-credentials/challenge/') {
          return http.Response(
            jsonEncode({
              'nonce': 'nonce-1',
              'expires_at': '2026-09-20T00:02:00Z',
            }),
            200,
          );
        }
        if (request.url.path == '/api/auth/device-credentials/login/') {
          return http.Response(
            jsonEncode({'access': 'bio-a', 'refresh': 'bio-r'}),
            200,
          );
        }
        if (request.method == 'PUT') {
          return http.Response(request.body, 200);
        }
        return http.Response(
          jsonEncode({'biometric_enabled': false}),
          200,
        );
      }),
      baseUrl: _baseUrl,
    );
    final vm = AuthViewModel(
      authService: AuthService(
        apiClient: api,
        tokenStorage: tokenStorage,
      ),
      deviceAuth: fake,
    );
    return (
      vm: vm,
      device: fake,
      storage: tokenStorage,
      requests: captured,
    );
  }

  group('G10.2 AuthService contract', () {
    test('AuthService implements DeviceCredentialAuthApi', () {
      final service = buildService(
        MockClient((_) async => http.Response('{}', 200)),
      );
      expect(service, isA<DeviceCredentialAuthApi>());
    });

    test('enrollDeviceCredential POSTs public_key never samples nor password',
        () async {
      http.Request? enroll;
      final service = buildService(
        MockClient((request) async {
          if (request.url.path == '/api/auth/device-credentials/') {
            enroll = request;
            return http.Response(
              jsonEncode(
                  {'id': 'cred-1', 'created_at': '2026-09-20T00:00:00Z'}),
              201,
            );
          }
          return http.Response('{}', 200);
        }),
      );

      final id = await (service as dynamic).enrollDeviceCredential(
        publicKey: 'PEM-PUBLIC',
        deviceLabel: 'Pixel-test',
      ) as String;

      expect(id, 'cred-1');
      expect(enroll, isNotNull);
      expect(enroll!.method, 'POST');
      expect(enroll!.url.path, '/api/auth/device-credentials/');
      final body = jsonDecode(enroll!.body) as Map<String, dynamic>;
      expect(body['public_key'], 'PEM-PUBLIC');
      expect(body['device_label'], 'Pixel-test');
      expect(body.containsKey('fingerprint'), isFalse);
      expect(body.containsKey('password'), isFalse);
    });

    test('loginWithDeviceCredential stores JWT like password login', () async {
      final storage = AuthTokenStorage.inMemory();
      late ApiClient api;
      final mock = MockClient((request) async {
        expect(request.url.path, '/api/auth/device-credentials/login/');
        expect(request.headers['Authorization'], isNull);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['credential_id'], 'cred-1');
        expect(body['nonce'], 'nonce-1');
        expect(body['signature'], 'sig-of-nonce-1');
        expect(body.containsKey('password'), isFalse);
        expect(body.containsKey('fingerprint'), isFalse);
        return http.Response(
          jsonEncode({'access': 'bio-a', 'refresh': 'bio-r'}),
          200,
        );
      });
      api = ApiClient(httpClient: mock, baseUrl: _baseUrl);
      final service = AuthService(apiClient: api, tokenStorage: storage);

      await (service as dynamic).loginWithDeviceCredential(
        credentialId: 'cred-1',
        nonce: 'nonce-1',
        signature: 'sig-of-nonce-1',
      );

      expect(api.accessToken, 'bio-a');
      expect(await storage.readRefreshToken(), 'bio-r');
    });
  });

  group('G10.2 AuthTokenStorage contract', () {
    test('AuthTokenStorage implements DeviceCredentialLocalStore', () {
      expect(AuthTokenStorage.inMemory(), isA<DeviceCredentialLocalStore>());
    });

    test('persists credential id and email hint without a password key',
        () async {
      final storage = AuthTokenStorage.inMemory();
      await (storage as dynamic).writeDeviceCredentialId('cred-1');
      await (storage as dynamic).writeEnrolledUserHint('ok@example.com');

      expect(await (storage as dynamic).readDeviceCredentialId(), 'cred-1');
      expect(
          await (storage as dynamic).readEnrolledUserHint(), 'ok@example.com');
      expect(await storage.readRefreshToken(), isNull);
    });

    test('logout refresh wipe does not require wiping enrollment hint',
        () async {
      final storage = AuthTokenStorage.inMemory();
      await storage.writeRefreshToken('r');
      await (storage as dynamic).writeDeviceCredentialId('cred-1');
      await (storage as dynamic).writeEnrolledUserHint('ok@example.com');

      await storage.writeRefreshToken(null);

      expect(await storage.readRefreshToken(), isNull);
      expect(await (storage as dynamic).readDeviceCredentialId(), 'cred-1');
      expect(
          await (storage as dynamic).readEnrolledUserHint(), 'ok@example.com');
    });
  });

  group('G10.2 AuthViewModel contract', () {
    test('AuthViewModel implements BiometricLoginViewModelApi', () {
      final h = harness();
      expect(h.vm, isA<BiometricLoginViewModelApi>());
    });

    test('lock flag alone does not offer biometric login', () async {
      final h = harness();
      await h.vm.loginWithPassword(
        email: 'ok@example.com',
        password: 'password1',
      );
      final enabled = await h.vm.setBiometricEnabled(true);
      expect(enabled, isTrue);
      expect(h.vm.biometricEnabled, isTrue);
      expect(
        h.requests.where(
          (r) => r.url.path == '/api/auth/device-credentials/login/',
        ),
        isEmpty,
      );
    });

    test('enrollDeviceCredential after local auth posts public_key', () async {
      final signer = FakeDeviceCredentialSigner();
      expect(signer.publicKey, isNotEmpty);
      final h = harness();
      await h.vm.loginWithPassword(
        email: 'ok@example.com',
        password: 'password1',
      );

      final ok = await (h.vm as dynamic).enrollDeviceCredential() as bool;

      expect(ok, isTrue);
      expect(h.device.authenticateCalls, greaterThan(0));
      final enrolls = h.requests.where(
        (r) =>
            r.method == 'POST' && r.url.path == '/api/auth/device-credentials/',
      );
      expect(enrolls, isNotEmpty);
      final body = jsonDecode(enrolls.first.body) as Map<String, dynamic>;
      expect(body['public_key'], isNotEmpty);
      expect(body.containsKey('fingerprint'), isFalse);
      expect(body.containsKey('password'), isFalse);
      expect((h.vm as dynamic).canOfferBiometricLogin, isTrue);
      expect((h.vm as dynamic).enrolledUserHint, 'ok@example.com');
    });

    test('loginWithBiometric does not call API when local auth fails',
        () async {
      final h = harness(
        device: FakeDeviceAuthenticator(
          available: true,
          outcome: FakeBiometricAuthOutcome.failed,
        ),
      );
      await (h.storage as dynamic).writeDeviceCredentialId('cred-1');
      await (h.storage as dynamic).writeEnrolledUserHint('ok@example.com');

      final ok = await (h.vm as dynamic).loginWithBiometric() as bool;

      expect(ok, isFalse);
      expect(h.vm.gate, isNot(AuthGate.app));
      expect(
        h.requests.where(
          (r) => r.url.path == '/api/auth/device-credentials/login/',
        ),
        isEmpty,
      );
    });

    test('logout then loginWithBiometric reaches AuthGate.app', () async {
      final h = harness();
      await h.vm.loginWithPassword(
        email: 'ok@example.com',
        password: 'password1',
      );
      await (h.vm as dynamic).enrollDeviceCredential();
      await h.vm.logout();
      expect(h.vm.gate, AuthGate.login);
      expect(await h.storage.readRefreshToken(), isNull);

      final ok = await (h.vm as dynamic).loginWithBiometric() as bool;

      expect(ok, isTrue);
      expect(h.vm.gate, AuthGate.app);
      expect(await h.storage.readRefreshToken(), 'bio-r');
      final logins = h.requests.where(
        (r) => r.url.path == '/api/auth/device-credentials/login/',
      );
      expect(logins, isNotEmpty);
      final body = jsonDecode(logins.first.body) as Map<String, dynamic>;
      expect(body.containsKey('password'), isFalse);
    });

    test('idle lock after biometric login is still lock, not a new login',
        () async {
      var now = DateTime.utc(2026, 9, 20, 12);
      final tokenStorage = AuthTokenStorage.inMemory();
      final fake = FakeDeviceAuthenticator(
        available: true,
        outcome: FakeBiometricAuthOutcome.success,
      );
      final api = ApiClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/auth/login/') {
            return http.Response(
              jsonEncode({'access': 'a', 'refresh': 'r'}),
              200,
            );
          }
          if (request.url.path == '/api/auth/device-credentials/') {
            return http.Response(
              jsonEncode({'id': 'cred-1', 'created_at': 't'}),
              201,
            );
          }
          if (request.url.path.endsWith('/challenge/')) {
            return http.Response(
              jsonEncode({'nonce': 'n', 'expires_at': 't'}),
              200,
            );
          }
          if (request.url.path.endsWith('/login/') &&
              request.url.path.contains('device-credentials')) {
            return http.Response(
              jsonEncode({'access': 'bio-a', 'refresh': 'bio-r'}),
              200,
            );
          }
          if (request.method == 'PUT') {
            return http.Response(
              jsonEncode({'biometric_enabled': true}),
              200,
            );
          }
          return http.Response(
            jsonEncode({'biometric_enabled': true}),
            200,
          );
        }),
        baseUrl: _baseUrl,
      );
      final vm = AuthViewModel(
        authService: AuthService(
          apiClient: api,
          tokenStorage: tokenStorage,
        ),
        deviceAuth: fake,
        clock: () => now,
      );
      await vm.loginWithPassword(
          email: 'ok@example.com', password: 'password1');
      await vm.setBiometricEnabled(true);
      await (vm as dynamic).enrollDeviceCredential();
      await vm.logout();
      await (vm as dynamic).loginWithBiometric();
      expect(vm.gate, AuthGate.app);

      await vm.handleAppLifecycle(AppLifecycleState.paused);
      now = now.add(AuthViewModel.inactivityLockTimeout);
      await vm.handleAppLifecycle(AppLifecycleState.resumed);

      expect(vm.gate, AuthGate.biometricLock);
      expect(await tokenStorage.readRefreshToken(), isNotNull);
    });
  });

  group('G10.2 LoginScreen UX', () {
    testWidgets('hides biometric button when there is no local credential',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AuthLoginScreen()),
      );
      expect(find.text('Ingresar con huella'), findsNothing);
    });

    testWidgets('shows Ingresar con huella when ViewModel can offer it',
        (tester) async {
      final handle = tester.ensureSemantics();
      final h = harness();
      try {
        await h.vm.loginWithPassword(
          email: 'ok@example.com',
          password: 'password1',
        );
        await h.vm.enrollDeviceCredential();
        await h.vm.logout();
        await tester.pumpWidget(
          ChangeNotifierProvider<AuthViewModel>.value(
            value: h.vm,
            child: const MaterialApp(home: AuthLoginScreen()),
          ),
        );
        await tester.pump();

        expect(find.text('Ingresar con huella'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            'Ingresar con huella. Continuar como ok@example.com',
          ),
          findsOneWidget,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('TalkBack announces enrolled email hint on biometric button',
        (tester) async {
      final handle = tester.ensureSemantics();
      final h = harness();
      try {
        await h.vm.loginWithPassword(
          email: 'ok@example.com',
          password: 'password1',
        );
        await h.vm.enrollDeviceCredential();
        await h.vm.logout();
        await tester.pumpWidget(
          ChangeNotifierProvider<AuthViewModel>.value(
            value: h.vm,
            child: const MaterialApp(home: AuthLoginScreen()),
          ),
        );
        await tester.pump();

        expect(
          find.bySemanticsLabel(
            RegExp(r'Ingresar con huella.*ok@example\.com'),
          ),
          findsOneWidget,
        );
      } finally {
        handle.dispose();
      }
    });
  });
}
