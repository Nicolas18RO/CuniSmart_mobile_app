import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/auth_token_storage.dart';
import 'package:frontend/viewmodels/auth_viewmodel.dart';

import 'fake_device_authenticator.dart';

/// G9.3 — contrato de candado por inactividad (TDD).
///
/// 15 minutos en segundo plano + sesión + biometría + hardware
/// → [AuthGate.biometricLock]. No es logout: los tokens siguen.
const _baseUrl = 'http://example.test';

void main() {
  final t0 = DateTime.utc(2026, 9, 20, 12, 0);

  test('inactivity lock timeout is 15 minutes', () {
    expect(
      AuthViewModel.inactivityLockTimeout,
      const Duration(minutes: 15),
    );
  });

  group('G9.3 inactivity lock', () {
    test('pauses 15 minutes with biometrics on and locks, without logout',
        () async {
      var now = t0;
      final storage = AuthTokenStorage.inMemory();
      final h = await _harness(
        clock: () => now,
        storage: storage,
      );
      await h.loginAndEnableBiometrics();
      expect(h.vm.gate, AuthGate.app);
      expect(await storage.readRefreshToken(), 'r');

      now = t0;
      await h.vm.handleAppLifecycle(AppLifecycleState.paused);
      now = t0.add(AuthViewModel.inactivityLockTimeout);
      await h.vm.handleAppLifecycle(AppLifecycleState.resumed);

      expect(h.vm.gate, AuthGate.biometricLock);
      expect(await storage.readRefreshToken(), 'r');

      final unlocked = await h.vm.unlockWithBiometric();
      expect(unlocked, isTrue);
      expect(h.vm.gate, AuthGate.app);
    });

    test('pauses just under 15 minutes and stays in the app', () async {
      var now = t0;
      final h = await _harness(clock: () => now);
      await h.loginAndEnableBiometrics();

      await h.vm.handleAppLifecycle(AppLifecycleState.paused);
      now = t0.add(AuthViewModel.inactivityLockTimeout - const Duration(seconds: 1));
      await h.vm.handleAppLifecycle(AppLifecycleState.resumed);

      expect(h.vm.gate, AuthGate.app);
    });

    test('does not lock when biometric preference is off', () async {
      var now = t0;
      final h = await _harness(clock: () => now);
      await h.loginOnly();

      await h.vm.handleAppLifecycle(AppLifecycleState.paused);
      now = t0.add(AuthViewModel.inactivityLockTimeout);
      await h.vm.handleAppLifecycle(AppLifecycleState.resumed);

      expect(h.vm.gate, AuthGate.app);
    });

    test('does not lock when hardware is unavailable', () async {
      var now = t0;
      final h = await _harness(
        clock: () => now,
        device: FakeDeviceAuthenticator(available: false),
      );
      await h.loginOnly();
      await h.vm.setBiometricEnabled(true);
      expect(h.vm.biometricEnabled, isFalse);

      await h.vm.handleAppLifecycle(AppLifecycleState.paused);
      now = t0.add(AuthViewModel.inactivityLockTimeout);
      await h.vm.handleAppLifecycle(AppLifecycleState.resumed);

      expect(h.vm.gate, AuthGate.app);
    });

    test('after bootstrap unlock, idle still locks using server preference',
        () async {
      var now = t0;
      final h = await _harness(
        clock: () => now,
        bootstrapBiometric: true,
      );
      await h.vm.runBootstrap();
      expect(h.vm.gate, AuthGate.biometricLock);
      expect(h.vm.biometricEnabled, isFalse);

      await h.vm.unlockWithBiometric();
      expect(h.vm.gate, AuthGate.app);

      await h.vm.handleAppLifecycle(AppLifecycleState.paused);
      now = t0.add(AuthViewModel.inactivityLockTimeout);
      await h.vm.handleAppLifecycle(AppLifecycleState.resumed);

      expect(h.vm.gate, AuthGate.biometricLock);
    });

    test('idle lock is not applied on the login gate', () async {
      var now = t0;
      final h = await _harness(clock: () => now);
      await h.loginAndEnableBiometrics();
      await h.vm.logout();
      expect(h.vm.gate, AuthGate.login);

      await h.vm.handleAppLifecycle(AppLifecycleState.paused);
      now = t0.add(AuthViewModel.inactivityLockTimeout);
      await h.vm.handleAppLifecycle(AppLifecycleState.resumed);

      expect(h.vm.gate, AuthGate.login);
    });
  });
}

class _Harness {
  _Harness({
    required this.vm,
    required this.device,
  });

  final AuthViewModel vm;
  final FakeDeviceAuthenticator device;

  Future<void> loginOnly() {
    return vm.loginWithPassword(email: 'ok@example.com', password: 'password1');
  }

  Future<void> loginAndEnableBiometrics() async {
    await loginOnly();
    final ok = await vm.setBiometricEnabled(true);
    expect(ok, isTrue);
  }
}

Future<_Harness> _harness({
  required DateTime Function() clock,
  FakeDeviceAuthenticator? device,
  AuthTokenStorage? storage,
  bool bootstrapBiometric = false,
}) async {
  final tokenStorage = storage ?? AuthTokenStorage.inMemory();
  if (bootstrapBiometric) {
    await tokenStorage.writeRefreshToken('r');
  }
  final fake = device ??
      FakeDeviceAuthenticator(
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
      if (request.url.path == '/api/auth/token/refresh/') {
        return http.Response(
          jsonEncode({'access': 'a', 'refresh': 'r'}),
          200,
        );
      }
      if (request.url.path == '/api/auth/bootstrap/') {
        return http.Response(
          jsonEncode({
            'session_valid': bootstrapBiometric,
            'auth_required': !bootstrapBiometric,
            'biometric_available': bootstrapBiometric,
          }),
          200,
        );
      }
      if (request.url.path == '/api/auth/logout/') {
        return http.Response('', 204);
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
    clock: clock,
  );
  return _Harness(vm: vm, device: fake);
}
