import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/auth_token_storage.dart';
import 'package:frontend/services/offline_authorization.dart';
import 'package:frontend/viewmodels/auth_viewmodel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_device_authenticator.dart';

void main() {
  late AuthTokenStorage storage;
  late BootTime clock;
  late int owner;
  late bool verified;
  late bool biometric;
  late int refreshStatus;
  late String? refreshCode;
  late List<AuthService> services;

  AuthService service(
      {Duration? timeout, Future<http.Response>? refreshResponse}) {
    final api = ApiClient(
      baseUrl: 'https://test.invalid',
      timeout: timeout,
      httpClient: MockClient((request) async {
        switch (request.url.path) {
          case '/api/auth/login/':
            return http.Response(
                '{"access":"access","refresh":"refresh"}', 200);
          case '/api/auth/token/refresh/':
            if (refreshResponse != null) return refreshResponse;
            return refreshStatus == 200
                ? http.Response('{"access":"new","refresh":"rotated"}', 200)
                : http.Response(
                    jsonEncode({'code': refreshCode, 'detail': 'Refresh'}),
                    refreshStatus);
          case '/api/auth/session/':
            return http.Response(
                jsonEncode({
                  'user': {'id': owner, 'is_verified': verified},
                  'settings': {'biometric_enabled': biometric},
                }),
                200);
          case '/api/auth/logout/':
            return http.Response('', 204);
          default:
            fail('Unexpected request: ${request.url.path}');
        }
      }),
    );
    final result = AuthService(
        apiClient: api, tokenStorage: storage, readBootTime: () async => clock);
    services.add(result);
    return result;
  }

  Future<void> signIn(AuthService auth) =>
      auth.login(email: 'a@test.invalid', password: 'password');

  setUp(() {
    storage = AuthTokenStorage.inMemory();
    clock = (
      bootCount: 7,
      elapsedMilliseconds: 100,
      installationId: 'installation'
    );
    owner = 1;
    verified = true;
    biometric = false;
    refreshStatus = 200;
    refreshCode = null;
    services = [];
  });

  tearDown(() async {
    for (final auth in services) {
      await auth.clearSession(notify: false);
    }
  });

  test('E6.1-01 verified account persists a 24 hour grant', () async {
    await signIn(service());
    final raw = jsonDecode((await storage.readOfflineAuthorization())!)
        as Map<String, dynamic>;
    final issued = DateTime.parse(raw['last_remote_verification_at'] as String);
    final expires =
        DateTime.parse(raw['offline_authorization_expires_at'] as String);
    expect(raw['user_id'], 1);
    expect(raw['is_verified'], true);
    expect(expires.difference(issued), const Duration(hours: 24));
  });

  test('E6.1-02/03/05 reopen on the same boot when backend is unavailable',
      () async {
    await signIn(service());
    final grant = await storage.readOfflineAuthorization();
    refreshStatus = 503;
    final restored = service();
    final result = await restored.bootstrap();
    expect(result.offline, isTrue);
    expect(restored.ownerId, 1);
    expect(restored.remoteVerified, isFalse);
    expect(await storage.readOfflineAuthorization(), grant);
    expect(await storage.readRefreshToken(), 'refresh');
  });

  test('E6.1-04 timeout preserves authorization and does not publish',
      () async {
    await signIn(service());
    final lostResponse = Completer<http.Response>();
    final restored = service(
        timeout: const Duration(milliseconds: 30),
        refreshResponse: lostResponse.future);
    expect((await restored.bootstrap()).offline, isTrue);
    expect(restored.remoteVerified, isFalse);
    lostResponse
        .complete(http.Response('{"access":"late","refresh":"late"}', 200));
    await Future<void>.delayed(Duration.zero);
    expect(await storage.readRefreshToken(), 'refresh');
  });

  test('E6.1-06/10/13 exact expiry and unreliable anchors block offline',
      () async {
    await signIn(service());
    refreshStatus = 503;
    for (final invalidClock in <BootTime>[
      (
        bootCount: 7,
        elapsedMilliseconds: 86400100,
        installationId: 'installation'
      ),
      (bootCount: 7, elapsedMilliseconds: 99, installationId: 'installation'),
      (bootCount: 8, elapsedMilliseconds: 100, installationId: 'installation'),
      (
        bootCount: 7,
        elapsedMilliseconds: 101,
        installationId: 'new-installation'
      ),
    ]) {
      clock = invalidClock;
      expect((await service().bootstrap()).sessionValid, isFalse);
    }
  });

  test(
      'E6.1-07 logout invalidates a refresh in flight and clears offline grant',
      () async {
    final pending = Completer<http.Response>();
    final auth = service(refreshResponse: pending.future);
    await signIn(auth);
    final refresh = auth.refreshFromStorage();
    await Future<void>.delayed(Duration.zero);
    final logout = auth.logout();
    expect(auth.ownerId, isNull);
    expect(auth.remoteVerified, isFalse);
    pending.complete(http.Response('{"access":"late","refresh":"late"}', 200));
    expect(await refresh, isFalse);
    await logout;
    expect(await storage.readRefreshToken(), isNull);
    expect(await storage.readOfflineAuthorization(), isNull);
  });

  test('E6.1-08 definitive rejection invalidates the stored grant', () async {
    await signIn(service());
    refreshStatus = 401;
    refreshCode = 'token_not_valid';
    expect((await service().bootstrap()).sessionValid, isFalse);
    expect(await storage.readOfflineAuthorization(), isNull);
  });

  test(
      'an ambiguous refresh rotation preserves the existing grant until expiry',
      () async {
    await signIn(service());
    final grant = await storage.readOfflineAuthorization();
    refreshStatus = 503;
    expect((await service().bootstrap()).offline, isTrue);
    refreshStatus = 401;
    refreshCode = 'token_not_valid';
    final restored = service();
    expect((await restored.bootstrap()).offline, isTrue);
    expect(restored.remoteVerified, isFalse);
    expect(await storage.readOfflineAuthorization(), grant);
  });

  test('an offline grant is unusable if its refresh is missing', () async {
    await signIn(service());
    await storage.writeRefreshToken(null);
    refreshStatus = 503;
    expect((await service().bootstrap()).sessionValid, isFalse);
  });

  test(
      'E6.1-09 a verified refresh for another owner cannot reuse authorization',
      () async {
    await signIn(service());
    owner = 2;
    expect((await service().bootstrap()).sessionValid, isFalse);
    expect(await storage.readOfflineAuthorization(), isNull);
  });

  test('E6.1-11 unavailable required device lock never opens offline Home',
      () async {
    biometric = true;
    await signIn(service());
    refreshStatus = 503;
    final auth = service();
    final vm = AuthViewModel(
        authService: auth,
        deviceAuth: FakeDeviceAuthenticator(available: false));
    addTearDown(vm.dispose);
    await vm.runBootstrap();
    expect(vm.gate, AuthGate.biometricLock);
    expect(auth.localDataUnlocked, isFalse);
  });

  test('E6.1-14 unverified account cannot receive a grant', () async {
    verified = false;
    final auth = service();
    await expectLater(signIn(auth), throwsException);
    expect(await storage.readOfflineAuthorization(), isNull);
    expect(auth.ownerId, isNull);
  });
}
