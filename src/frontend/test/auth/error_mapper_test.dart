import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:frontend/core/errors/api_exception.dart';
import 'package:frontend/core/errors/auth_ui_error.dart';
import 'package:frontend/core/errors/error_mapper.dart';

void main() {
  group('ErrorMapper', () {
    test('maps invalid_credentials to a user-facing login error', () {
      final raw = jsonEncode({
        'detail': 'Invalid credentials.',
        'code': 'invalid_credentials',
      });
      final ui = ErrorMapper.map(
        ApiException(raw, statusCode: 400),
      );

      expect(ui.kind, AuthUiKind.invalidCredentials);
      expect(ui.title, 'No se pudo iniciar sesión');
      expect(
        ui.message,
        'El correo o la contraseña son incorrectos. '
        'Verifica tus datos e inténtalo nuevamente.',
      );
      expect(ui.action, 'Entendido');
      expect(ui.technicalCode, 'invalid_credentials');
      expectCleanUserFacingText(ui);
    });

    test('maps email_not_verified without exposing technical payload', () {
      final raw = jsonEncode({
        'detail': 'Email not verified',
        'code': 'email_not_verified',
      });
      final ui = ErrorMapper.map(
        ApiException(raw, statusCode: 400),
      );

      expect(ui.kind, AuthUiKind.emailNotVerified);
      expect(ui.title, 'Correo no verificado');
      expect(
        ui.message,
        'Debes verificar tu correo electrónico antes de iniciar sesión.',
      );
      expect(ui.action, 'Reenviar código');
      expect(ui.technicalCode, 'email_not_verified');
      expectCleanUserFacingText(ui);
    });

    test('maps network failure to a connection error', () {
      final ui = ErrorMapper.map(
        const SocketException('Failed host lookup'),
      );

      expect(ui.kind, AuthUiKind.network);
      expect(ui.title, 'Sin conexión');
      expect(
        ui.message,
        'No pudimos comunicarnos con CuniSmart. '
        'Revisa tu conexión a Internet e inténtalo nuevamente.',
      );
      expectCleanUserFacingText(ui);
      expect(ui.message, isNot(contains('Failed host lookup')));
    });

    test('maps http ClientException as network error', () {
      final ui = ErrorMapper.map(
        http.ClientException(
          'Connection refused',
          Uri.parse('http://example.test/api/auth/login/'),
        ),
      );

      expect(ui.kind, AuthUiKind.network);
      expectCleanUserFacingText(ui);
    });

    test('maps HTTP 5xx to a server error', () {
      final raw = jsonEncode({
        'detail': 'Internal Server Error',
        'traceback': 'Traceback (most recent call last): ...',
      });
      final ui = ErrorMapper.map(
        ApiException(raw, statusCode: 500),
      );

      expect(ui.kind, AuthUiKind.server);
      expect(ui.title, 'Servicio temporalmente no disponible');
      expect(
        ui.message,
        'No pudimos completar la operación en este momento. '
        'Inténtalo nuevamente más tarde.',
      );
      expectCleanUserFacingText(ui);
      expect(ui.message, isNot(contains('Internal Server Error')));
      expect(ui.message, isNot(contains('Traceback')));
    });

    test('maps unknown failures to a generic user-facing error', () {
      final ui = ErrorMapper.map(
        ApiException('not-json-garbage <<<>>>', statusCode: 400),
      );

      expect(ui.kind, AuthUiKind.unknown);
      expect(ui.title, 'Algo salió mal');
      expect(
        ui.message,
        'Ocurrió un problema inesperado. Inténtalo nuevamente.',
      );
      expectCleanUserFacingText(ui);
      expect(ui.message, isNot(contains('not-json-garbage')));
    });

    test('maps ApiException network code to a connection error', () {
      final ui = ErrorMapper.map(
        ApiException('Connection refused', code: 'network'),
      );

      expect(ui.kind, AuthUiKind.network);
      expect(ui.title, 'Sin conexión');
      expectCleanUserFacingText(ui);
      expect(ui.message, isNot(contains('Connection refused')));
    });

    test('maps duplicate email in register context without exposing English detail', () {
      final raw = jsonEncode({
        'detail': 'A user with this email already exists.',
        'code': 'validation_error',
      });
      final ui = ErrorMapper.map(
        ApiException(raw, statusCode: 400),
        context: AuthErrorContext.register,
      );

      expect(ui.kind, AuthUiKind.emailAlreadyRegistered);
      expect(ui.title, 'Correo no disponible');
      expect(
        ui.message,
        'Este correo ya está registrado. Intenta iniciar sesión o recuperar tu contraseña.',
      );
      expectCleanUserFacingText(ui);
      expect(ui.message, isNot(contains('already exists')));
    });

    test('maps recovery_code_invalid without exposing technical payload', () {
      final raw = jsonEncode({
        'detail': 'Invalid recovery code.',
        'code': 'recovery_code_invalid',
      });
      final ui = ErrorMapper.map(ApiException(raw, statusCode: 400));

      expect(ui.kind, AuthUiKind.resetCodeInvalid);
      expect(ui.title, 'Código incorrecto');
      expect(
        ui.message,
        'El código de recuperación no es válido. Verifica el código enviado a tu correo.',
      );
      expectCleanUserFacingText(ui);
      expect(ui.message, isNot(contains('Invalid recovery code')));
    });

    test('maps recovery_code_expired without exposing technical payload', () {
      final raw = jsonEncode({
        'detail': 'Recovery code expired.',
        'code': 'recovery_code_expired',
      });
      final ui = ErrorMapper.map(ApiException(raw, statusCode: 400));

      expect(ui.kind, AuthUiKind.resetCodeExpired);
      expect(ui.title, 'Código expirado');
      expect(
        ui.message,
        'El código de recuperación ya no es válido. Solicita uno nuevo.',
      );
      expectCleanUserFacingText(ui);
      expect(ui.message, isNot(contains('Recovery code expired')));
    });

    test('maps reset validation_error to a combined recovery-code message', () {
      final raw = jsonEncode({
        'detail': 'Invalid or expired recovery token.',
        'code': 'validation_error',
      });
      final ui = ErrorMapper.map(
        ApiException(raw, statusCode: 400),
        context: AuthErrorContext.passwordReset,
      );

      expect(ui.kind, AuthUiKind.resetCodeInvalid);
      expect(ui.title, 'Código incorrecto');
      expect(
        ui.message,
        'El código de recuperación no es válido o ya venció. Solicita uno nuevo.',
      );
      expectCleanUserFacingText(ui);
      expect(ui.message, isNot(contains('recovery token')));
    });

    test('maps verification_code_invalid without exposing technical payload', () {
      final raw = jsonEncode({
        'detail': 'Invalid verification code.',
        'code': 'verification_code_invalid',
      });
      final ui = ErrorMapper.map(ApiException(raw, statusCode: 400));

      expect(ui.kind, AuthUiKind.verificationCodeInvalid);
      expect(ui.title, 'Código incorrecto');
      expect(
        ui.message,
        'El código ingresado no es válido. Revisa el correo e inténtalo nuevamente.',
      );
      expect(ui.action, 'Entendido');
      expect(ui.technicalCode, 'verification_code_invalid');
      expectCleanUserFacingText(ui);
      expect(ui.message, isNot(contains('Invalid verification code')));
    });

    test('maps verification_code_expired to a resend-oriented error', () {
      final raw = jsonEncode({
        'detail': 'Verification code expired.',
        'code': 'verification_code_expired',
      });
      final ui = ErrorMapper.map(ApiException(raw, statusCode: 400));

      expect(ui.kind, AuthUiKind.verificationCodeExpired);
      expect(ui.title, 'Código expirado');
      expect(
        ui.message,
        'Este código ya no es válido. Solicita un nuevo código de verificación.',
      );
      expect(ui.action, 'Enviar nuevo código');
      expect(ui.technicalCode, 'verification_code_expired');
      expectCleanUserFacingText(ui);
      expect(ui.message, isNot(contains('Verification code expired')));
    });

    test('maps HTTP 429 to a too-many-attempts error', () {
      final raw = jsonEncode({
        'detail': 'Request was throttled.',
        'code': 'validation_error',
      });
      final ui = ErrorMapper.map(ApiException(raw, statusCode: 429));

      expect(ui.kind, AuthUiKind.tooManyAttempts);
      expect(ui.title, 'Demasiados intentos');
      expect(
        ui.message,
        'Has realizado demasiados intentos. Espera unos minutos y vuelve a intentarlo.',
      );
      expectCleanUserFacingText(ui);
      expect(ui.message, isNot(contains('throttled')));
    });
  });
}

void expectCleanUserFacingText(AuthUiError ui) {
  final parts = [ui.title, ui.message, ui.action];
  for (final part in parts) {
    expect(part, isNot(contains('ApiException')));
    expect(part, isNot(contains('{')));
    expect(part, isNot(contains('}')));
    expect(part, isNot(contains('"detail"')));
    expect(part, isNot(contains('"code"')));
    expect(part, isNot(contains('invalid_credentials')));
    expect(part, isNot(contains('email_not_verified')));
    expect(part, isNot(contains('verification_code_invalid')));
    expect(part, isNot(contains('verification_code_expired')));
    expect(part, isNot(contains('recovery_code_invalid')));
    expect(part, isNot(contains('recovery_code_expired')));
    expect(part, isNot(contains('SocketException')));
    expect(part, isNot(contains('ClientException')));
  }
}
