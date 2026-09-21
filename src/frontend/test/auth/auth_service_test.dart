import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/errors/api_exception.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/auth_token_storage.dart';

void main() {
  const baseUrl = 'http://example.test';

  AuthService buildService(MockClient mock, {AuthTokenStorage? storage}) {
    final api = ApiClient(httpClient: mock, baseUrl: baseUrl);
    return AuthService(
      apiClient: api,
      tokenStorage: storage ?? AuthTokenStorage.inMemory(),
    );
  }

  test('bootstrap without refresh returns logged-out shape', () async {
    final mock = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/auth/bootstrap/');
      expect(request.headers['Authorization'], isNull);
      return http.Response(
        jsonEncode({
          'session_valid': false,
          'auth_required': true,
          'biometric_available': false,
        }),
        200,
      );
    });
    final service = buildService(mock);
    final result = await service.bootstrap();
    expect(result.sessionValid, isFalse);
    expect(result.authRequired, isTrue);
    expect(result.biometricAvailable, isFalse);
  });

  test('login stores access in memory and refresh in storage', () async {
    final storage = AuthTokenStorage.inMemory();
    final mock = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/auth/login/');
      return http.Response(
        jsonEncode({'access': 'acc-1', 'refresh': 'ref-1'}),
        200,
      );
    });
    final api = ApiClient(httpClient: mock, baseUrl: baseUrl);
    final service = AuthService(apiClient: api, tokenStorage: storage);

    await service.login(email: 'a@b.com', password: 'secret');
    expect(api.accessToken, 'acc-1');
    expect(await storage.readRefreshToken(), 'ref-1');
  });

  test('clearSession wipes access and refresh', () async {
    final storage = AuthTokenStorage.inMemory();
    await storage.writeRefreshToken('ref');
    final api = ApiClient(
      httpClient: MockClient((_) async => http.Response('{}', 200)),
      baseUrl: baseUrl,
    )..accessToken = 'acc';
    final service = AuthService(apiClient: api, tokenStorage: storage);

    await service.clearSession();
    expect(api.accessToken, isNull);
    expect(await storage.readRefreshToken(), isNull);
  });

  test('logout posts refresh then clears local tokens', () async {
    http.Request? logoutReq;
    final storage = AuthTokenStorage.inMemory();
    final mock = MockClient((request) async {
      if (request.url.path == '/api/auth/login/') {
        return http.Response(
          jsonEncode({'access': 'acc-1', 'refresh': 'ref-1'}),
          200,
        );
      }
      if (request.url.path == '/api/auth/logout/') {
        logoutReq = request;
        return http.Response('', 204);
      }
      return http.Response('unexpected', 500);
    });
    final api = ApiClient(httpClient: mock, baseUrl: baseUrl);
    final service = AuthService(apiClient: api, tokenStorage: storage);
    await service.login(email: 'a@b.com', password: 'secret');

    await service.logout();
    expect(logoutReq, isNotNull);
    expect(logoutReq!.method, 'POST');
    expect(logoutReq!.headers['Authorization'], 'Bearer acc-1');
    expect(jsonDecode(logoutReq!.body)['refresh'], 'ref-1');
    expect(api.accessToken, isNull);
    expect(await storage.readRefreshToken(), isNull);
  });

  test('logout still clears tokens when remote call fails', () async {
    final storage = AuthTokenStorage.inMemory();
    final mock = MockClient((request) async {
      if (request.url.path == '/api/auth/login/') {
        return http.Response(
          jsonEncode({'access': 'acc-1', 'refresh': 'ref-1'}),
          200,
        );
      }
      return http.Response('no', 500);
    });
    final api = ApiClient(httpClient: mock, baseUrl: baseUrl);
    final service = AuthService(apiClient: api, tokenStorage: storage);
    await service.login(email: 'a@b.com', password: 'secret');

    await service.logout();
    expect(api.accessToken, isNull);
    expect(await storage.readRefreshToken(), isNull);
  });

  test('failed 401 refresh clears session and notifies', () async {
    final storage = AuthTokenStorage.inMemory();
    await storage.writeRefreshToken('stale');
    final api = ApiClient(
      httpClient: MockClient((request) async {
        return http.Response('unauthorized', 401);
      }),
      baseUrl: baseUrl,
    )..accessToken = 'expired';
    final service = AuthService(apiClient: api, tokenStorage: storage);
    var invalid = 0;
    service.onSessionInvalid = () => invalid += 1;
    api.onTokenRefresh = service.refreshFromStorage;

    await expectLater(
      api.get('/api/rabbits/'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
    expect(api.accessToken, isNull);
    expect(await storage.readRefreshToken(), isNull);
    expect(invalid, 1);
  });

  test('requestPasswordReset posts email without auth header', () async {
    http.Request? captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'detail': 'If an account exists, a recovery message was sent.',
        }),
        200,
      );
    });
    final service = buildService(mock);
    await service.requestPasswordReset(email: 'a@b.com');
    expect(captured, isNotNull);
    expect(captured!.method, 'POST');
    expect(captured!.url.path, '/api/auth/password-reset/request/');
    expect(captured!.headers['Authorization'], isNull);
    expect(jsonDecode(captured!.body)['email'], 'a@b.com');
  });

  test('confirmPasswordReset posts email, code and new_password', () async {
    http.Request? captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'detail': 'Password updated. You can sign in with your new password.'}),
        200,
      );
    });
    final service = buildService(mock);
    await service.confirmPasswordReset(
      email: 'a@b.com',
      code: '482731',
      newPassword: 'newpass12',
    );
    expect(captured!.url.path, '/api/auth/password-reset/confirm/');
    expect(captured!.headers['Authorization'], isNull);
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['email'], 'a@b.com');
    expect(body['code'], '482731');
    expect(body['new_password'], 'newpass12');
    expect(body.containsKey('token'), isFalse);
  });

  test('verifyEmailCode posts email and code without auth header', () async {
    http.Request? captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'detail': 'Email verified successfully.',
          'verified': true,
        }),
        200,
      );
    });
    await buildService(mock).verifyEmailCode(
      email: 'a@b.com',
      code: '482731',
    );
    expect(captured, isNotNull);
    expect(captured!.method, 'POST');
    expect(captured!.url.path, '/api/auth/verify-email-code/');
    expect(captured!.headers['Authorization'], isNull);
    expect(jsonDecode(captured!.body), {
      'email': 'a@b.com',
      'code': '482731',
    });
  });

  test('resendVerificationEmail posts email without auth header', () async {
    http.Request? captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'detail':
              'If an account exists and requires verification, a message was sent.',
        }),
        200,
      );
    });
    await buildService(mock).resendVerificationEmail(email: 'a@b.com');
    expect(captured!.method, 'POST');
    expect(captured!.url.path, '/api/auth/resend-verification/');
    expect(captured!.headers['Authorization'], isNull);
    expect(jsonDecode(captured!.body)['email'], 'a@b.com');
  });

  test('updateBiometricEnabled sends only the boolean flag', () async {
    http.Request? captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'biometric_enabled': true}), 200);
    });
    final service = buildService(mock);
    await service.updateBiometricEnabled(true);
    expect(captured!.method, 'PUT');
    expect(captured!.url.path, '/api/users/biometric-status/');
    expect(jsonDecode(captured!.body), {'biometric_enabled': true});
  });

  test('fetchBiometricEnabled reads server flag', () async {
    final mock = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/users/biometric-status/');
      return http.Response(jsonEncode({'biometric_enabled': false}), 200);
    });
    final enabled = await buildService(mock).fetchBiometricEnabled();
    expect(enabled, isFalse);
  });
}
