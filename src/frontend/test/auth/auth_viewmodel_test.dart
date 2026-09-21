import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/errors/api_exception.dart';
import 'package:frontend/core/errors/auth_ui_error.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/auth_token_storage.dart';
import 'package:frontend/viewmodels/auth_viewmodel.dart';

import 'fake_device_authenticator.dart';

void main() {
  const baseUrl = 'http://example.test';

  AuthViewModel viewModelWith(MockClient mock) {
    final api = ApiClient(httpClient: mock, baseUrl: baseUrl);
    final service = AuthService(
      apiClient: api,
      tokenStorage: AuthTokenStorage.inMemory(),
    );
    return AuthViewModel(authService: service);
  }

  test('runBootstrap with invalid session sets AuthGate.login', () async {
    final vm = viewModelWith(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'session_valid': false,
            'auth_required': true,
            'biometric_available': false,
          }),
          200,
        );
      }),
    );

    await vm.runBootstrap();
    expect(vm.gate, AuthGate.login);
    expect(vm.lastBootstrap?.sessionValid, isFalse);
  });

  test('loginWithPassword sets AuthGate.app', () async {
    final vm = viewModelWith(
      MockClient((request) async {
        expect(request.url.path, '/api/auth/login/');
        return http.Response(
          jsonEncode({'access': 'a', 'refresh': 'r'}),
          200,
        );
      }),
    );

    await vm.loginWithPassword(email: 'ok@example.com', password: 'password1');
    expect(vm.gate, AuthGate.app);
    expect(vm.lastError, isNull);
    expect(vm.loginStatus, AuthSubmitStatus.success);
    expect(vm.isSubmitting, isFalse);
  });

  test('loginWithPassword maps invalid_credentials to a user-facing error', () async {
    final vm = viewModelWith(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'Invalid credentials.',
            'code': 'invalid_credentials',
          }),
          400,
        );
      }),
    );

    await expectLater(
      vm.loginWithPassword(email: 'a@b.com', password: 'bad'),
      throwsA(isA<ApiException>()),
    );

    expect(vm.gate, isNot(AuthGate.app));
    expect(vm.loginStatus, AuthSubmitStatus.error);
    expect(vm.isSubmitting, isFalse);
    expect(vm.lastError, isNotNull);
    expect(vm.lastError!.kind, AuthUiKind.invalidCredentials);
    expect(vm.lastError!.title, 'No se pudo iniciar sesión');
    expect(
      vm.lastError!.message,
      'El correo o la contraseña son incorrectos. '
      'Verifica tus datos e inténtalo nuevamente.',
    );
    expect(vm.lastError!.message, isNot(contains('ApiException')));
    expect(vm.lastError!.message, isNot(contains('invalid_credentials')));
    expect(vm.lastError!.message, isNot(contains('{')));
  });

  test('loginWithPassword maps email_not_verified without opening the app', () async {
    final vm = viewModelWith(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'Email not verified',
            'code': 'email_not_verified',
          }),
          400,
        );
      }),
    );

    await expectLater(
      vm.loginWithPassword(email: 'a@b.com', password: 'password1'),
      throwsA(isA<ApiException>()),
    );

    expect(vm.gate, isNot(AuthGate.app));
    expect(vm.lastError!.kind, AuthUiKind.emailNotVerified);
    expect(vm.lastError!.title, 'Correo no verificado');
    expect(vm.lastError!.technicalCode, 'email_not_verified');
    expect(vm.lastError!.message, isNot(contains('Email not verified')));
  });

  test('loginWithPassword maps network failure to a connection error', () async {
    final vm = viewModelWith(
      MockClient((request) async {
        throw http.ClientException(
          'Connection refused',
          request.url,
        );
      }),
    );

    await expectLater(
      vm.loginWithPassword(email: 'a@b.com', password: 'password1'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'network')),
    );

    expect(vm.gate, isNot(AuthGate.app));
    expect(vm.lastError!.kind, AuthUiKind.network);
    expect(vm.lastError!.title, 'Sin conexión');
    expect(vm.lastError!.message, isNot(contains('Connection refused')));
  });

  test('loginWithPassword maps HTTP 500 to a server error', () async {
    final vm = viewModelWith(
      MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Internal Server Error'}),
          500,
        );
      }),
    );

    await expectLater(
      vm.loginWithPassword(email: 'a@b.com', password: 'password1'),
      throwsA(isA<ApiException>()),
    );

    expect(vm.gate, isNot(AuthGate.app));
    expect(vm.lastError!.kind, AuthUiKind.server);
    expect(vm.lastError!.title, 'Servicio temporalmente no disponible');
    expect(vm.lastError!.message, isNot(contains('Internal Server Error')));
  });

  test('successful login after a failure clears lastError', () async {
    var calls = 0;
    final vm = viewModelWith(
      MockClient((request) async {
        calls += 1;
        if (calls == 1) {
          return http.Response(
            jsonEncode({
              'detail': 'Invalid credentials.',
              'code': 'invalid_credentials',
            }),
            400,
          );
        }
        return http.Response(
          jsonEncode({'access': 'a', 'refresh': 'r'}),
          200,
        );
      }),
    );

    await expectLater(
      vm.loginWithPassword(email: 'a@b.com', password: 'bad'),
      throwsA(isA<ApiException>()),
    );
    expect(vm.lastError, isNotNull);

    await vm.loginWithPassword(email: 'ok@example.com', password: 'password1');
    expect(vm.gate, AuthGate.app);
    expect(vm.lastError, isNull);
    expect(vm.loginStatus, AuthSubmitStatus.success);
  });

  test('register maps duplicate email to a user-facing error', () async {
    final vm = viewModelWith(
      MockClient((request) async {
        expect(request.url.path, '/api/auth/register/');
        return http.Response(
          jsonEncode({
            'detail': 'A user with this email already exists.',
            'code': 'validation_error',
          }),
          400,
        );
      }),
    );

    await expectLater(
      vm.register(email: 'dup@example.com', password: 'password1'),
      throwsA(isA<ApiException>()),
    );
    expect(vm.lastError!.kind, AuthUiKind.emailAlreadyRegistered);
    expect(vm.lastError!.message, isNot(contains('already exists')));
    expect(vm.lastError!.message, isNot(contains('ApiException')));
  });

  test('confirmPasswordReset maps invalid recovery code without exposing JSON', () async {
    final vm = viewModelWith(
      MockClient((request) async {
        expect(request.url.path, '/api/auth/password-reset/confirm/');
        return http.Response(
          jsonEncode({
            'detail': 'Invalid recovery code.',
            'code': 'recovery_code_invalid',
          }),
          400,
        );
      }),
    );

    await expectLater(
      vm.confirmPasswordReset(
        email: 'a@b.com',
        code: '000000',
        newPassword: 'newpass12',
      ),
      throwsA(isA<ApiException>()),
    );
    expect(vm.lastError!.kind, AuthUiKind.resetCodeInvalid);
    expect(vm.lastError!.message, isNot(contains('Invalid recovery code')));
    expect(vm.lastError!.message, isNot(contains('ApiException')));
  });

  test('requestPasswordReset maps HTTP 500 to a server error', () async {
    final vm = viewModelWith(
      MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Internal Server Error'}),
          500,
        );
      }),
    );

    await expectLater(
      vm.requestPasswordReset(email: 'a@b.com'),
      throwsA(isA<ApiException>()),
    );
    expect(vm.lastError!.kind, AuthUiKind.server);
    expect(vm.lastError!.message, isNot(contains('Internal Server Error')));
  });

  test('verifyEmailCode success does not open the app', () async {
    final vm = viewModelWith(
      MockClient((request) async {
        expect(request.url.path, '/api/auth/verify-email-code/');
        return http.Response(
          jsonEncode({
            'detail': 'Email verified successfully.',
            'verified': true,
          }),
          200,
        );
      }),
    );

    await vm.verifyEmailCode(email: 'ok@example.com', code: '482731');
    expect(vm.gate, isNot(AuthGate.app));
    expect(vm.lastError, isNull);
    expect(vm.loginStatus, AuthSubmitStatus.success);
  });

  test('verifyEmailCode maps invalid code without exposing JSON', () async {
    final vm = viewModelWith(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'Invalid verification code.',
            'code': 'verification_code_invalid',
          }),
          400,
        );
      }),
    );

    await expectLater(
      vm.verifyEmailCode(email: 'a@b.com', code: '000000'),
      throwsA(isA<ApiException>()),
    );
    expect(vm.lastError!.kind, AuthUiKind.verificationCodeInvalid);
    expect(vm.lastError!.title, 'Código incorrecto');
    expect(vm.lastError!.message, isNot(contains('Invalid verification code')));
    expect(vm.lastError!.message, isNot(contains('ApiException')));
    expect(vm.gate, isNot(AuthGate.app));
  });

  test('verifyEmailCode maps expired code', () async {
    final vm = viewModelWith(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'Verification code expired.',
            'code': 'verification_code_expired',
          }),
          400,
        );
      }),
    );

    await expectLater(
      vm.verifyEmailCode(email: 'a@b.com', code: '482731'),
      throwsA(isA<ApiException>()),
    );
    expect(vm.lastError!.kind, AuthUiKind.verificationCodeExpired);
    expect(vm.lastError!.title, 'Código expirado');
    expect(vm.lastError!.action, 'Enviar nuevo código');
    expect(vm.lastError!.message, isNot(contains('Verification code expired')));
  });

  test('logout posts remote then sets AuthGate.login', () async {
    http.Request? logoutReq;
    final vm = viewModelWith(
      MockClient((request) async {
        if (request.url.path == '/api/auth/login/') {
          return http.Response(
            jsonEncode({'access': 'a', 'refresh': 'r'}),
            200,
          );
        }
        if (request.url.path == '/api/auth/logout/') {
          logoutReq = request;
          return http.Response('', 204);
        }
        return http.Response('no', 500);
      }),
    );
    await vm.loginWithPassword(email: 'ok@example.com', password: 'password1');
    await vm.logout();
    expect(logoutReq, isNotNull);
    expect(jsonDecode(logoutReq!.body)['refresh'], 'r');
    expect(vm.gate, AuthGate.login);
  });

  test('failed refresh after 401 forces AuthGate.login', () async {
    final api = ApiClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/auth/login/') {
          return http.Response(
            jsonEncode({'access': 'a', 'refresh': 'r'}),
            200,
          );
        }
        return http.Response('unauthorized', 401);
      }),
      baseUrl: baseUrl,
    );
    final service = AuthService(
      apiClient: api,
      tokenStorage: AuthTokenStorage.inMemory(),
    );
    api.onTokenRefresh = service.refreshFromStorage;
    final vm = AuthViewModel(authService: service);

    await vm.loginWithPassword(email: 'ok@example.com', password: 'password1');
    expect(vm.gate, AuthGate.app);

    await expectLater(
      api.get('/api/rabbits/'),
      throwsA(isA<ApiException>()),
    );
    expect(vm.gate, AuthGate.login);
  });

  test('bootstrap with biometric flag and hardware sets lock', () async {
    final api = ApiClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'session_valid': true,
            'auth_required': false,
            'biometric_available': true,
          }),
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
      deviceAuth: FakeDeviceAuthenticator(available: true),
    );
    await vm.runBootstrap();
    expect(vm.gate, AuthGate.biometricLock);
  });

  test('bootstrap with biometric flag but no hardware sets app', () async {
    final api = ApiClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'session_valid': true,
            'auth_required': false,
            'biometric_available': true,
          }),
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
      deviceAuth: FakeDeviceAuthenticator(available: false),
    );
    await vm.runBootstrap();
    expect(vm.gate, AuthGate.app);
  });

  test('failed unlock does not enter app', () async {
    final api = ApiClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'session_valid': true,
            'auth_required': false,
            'biometric_available': true,
          }),
          200,
        );
      }),
      baseUrl: baseUrl,
    );
    final device = FakeDeviceAuthenticator(available: true, authSucceeds: false);
    final vm = AuthViewModel(
      authService: AuthService(
        apiClient: api,
        tokenStorage: AuthTokenStorage.inMemory(),
      ),
      deviceAuth: device,
    );
    await vm.runBootstrap();
    final ok = await vm.unlockWithBiometric();
    expect(ok, isFalse);
    expect(vm.gate, AuthGate.biometricLock);
  });

  test('enabling biometric requires device prompt then PUT flag only', () async {
    http.Request? putReq;
    final api = ApiClient(
      httpClient: MockClient((request) async {
        if (request.method == 'PUT') {
          putReq = request;
          return http.Response(jsonEncode({'biometric_enabled': true}), 200);
        }
        return http.Response(jsonEncode({'biometric_enabled': false}), 200);
      }),
      baseUrl: baseUrl,
    );
    final device = FakeDeviceAuthenticator(available: true, authSucceeds: true);
    final vm = AuthViewModel(
      authService: AuthService(
        apiClient: api,
        tokenStorage: AuthTokenStorage.inMemory(),
      ),
      deviceAuth: device,
    );

    final ok = await vm.setBiometricEnabled(true);
    expect(ok, isTrue);
    expect(device.authenticateCalls, 1);
    expect(vm.biometricEnabled, isTrue);
    expect(putReq, isNotNull);
    expect(jsonDecode(putReq!.body), {'biometric_enabled': true});
  });

  test('failed device prompt does not enable biometric', () async {
    var puts = 0;
    final api = ApiClient(
      httpClient: MockClient((request) async {
        if (request.method == 'PUT') {
          puts += 1;
          return http.Response(jsonEncode({'biometric_enabled': true}), 200);
        }
        return http.Response(jsonEncode({'biometric_enabled': false}), 200);
      }),
      baseUrl: baseUrl,
    );
    final device = FakeDeviceAuthenticator(available: true, authSucceeds: false);
    final vm = AuthViewModel(
      authService: AuthService(
        apiClient: api,
        tokenStorage: AuthTokenStorage.inMemory(),
      ),
      deviceAuth: device,
    );

    final ok = await vm.setBiometricEnabled(true);
    expect(ok, isFalse);
    expect(puts, 0);
    expect(vm.biometricEnabled, isFalse);
  });

  test('missing hardware does not enable biometric', () async {
    var puts = 0;
    final api = ApiClient(
      httpClient: MockClient((request) async {
        if (request.method == 'PUT') puts += 1;
        return http.Response(jsonEncode({'biometric_enabled': false}), 200);
      }),
      baseUrl: baseUrl,
    );
    final device = FakeDeviceAuthenticator(available: false);
    final vm = AuthViewModel(
      authService: AuthService(
        apiClient: api,
        tokenStorage: AuthTokenStorage.inMemory(),
      ),
      deviceAuth: device,
    );

    final ok = await vm.setBiometricEnabled(true);
    expect(ok, isFalse);
    expect(device.authenticateCalls, 0);
    expect(puts, 0);
  });
}
