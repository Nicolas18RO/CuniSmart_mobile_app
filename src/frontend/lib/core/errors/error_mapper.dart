import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'auth_ui_error.dart';

/// Distinguishes flows that share generic backend codes such as `validation_error`.
enum AuthErrorContext {
  login,
  register,
  passwordReset,
  resendVerification,
  emailVerification,
}

/// Translates technical failures into [AuthUiError] for the UI.
class ErrorMapper {
  ErrorMapper._();

  static AuthUiError map(
    Object error, {
    AuthErrorContext? context,
  }) {
    if (error is ApiException) {
      final mapped = _fromApiException(error, context);
      if (mapped != null) return mapped;
    }

    if (_isNetwork(error)) {
      return const AuthUiError(
        kind: AuthUiKind.network,
        title: 'Sin conexión',
        message:
            'No pudimos comunicarnos con CuniSmart. '
            'Revisa tu conexión a Internet e inténtalo nuevamente.',
        action: 'Entendido',
        technicalCode: 'network',
      );
    }

    return const AuthUiError(
      kind: AuthUiKind.unknown,
      title: 'Algo salió mal',
      message: 'Ocurrió un problema inesperado. Inténtalo nuevamente.',
      action: 'Entendido',
    );
  }

  static AuthUiError? _fromApiException(
    ApiException error,
    AuthErrorContext? context,
  ) {
    switch (error.code) {
      case 'invalid_credentials':
        return AuthUiError(
          kind: AuthUiKind.invalidCredentials,
          title: 'No se pudo iniciar sesión',
          message:
              'El correo o la contraseña son incorrectos. '
              'Verifica tus datos e inténtalo nuevamente.',
          action: 'Entendido',
          technicalCode: error.code,
        );
      case 'email_not_verified':
        return AuthUiError(
          kind: AuthUiKind.emailNotVerified,
          title: 'Correo no verificado',
          message:
              'Debes verificar tu correo electrónico antes de iniciar sesión.',
          action: 'Reenviar código',
          technicalCode: error.code,
        );
      case 'network':
        return AuthUiError(
          kind: AuthUiKind.network,
          title: 'Sin conexión',
          message:
              'No pudimos comunicarnos con CuniSmart. '
              'Revisa tu conexión a Internet e inténtalo nuevamente.',
          action: 'Entendido',
          technicalCode: error.code,
        );
      case 'verification_code_invalid':
        return AuthUiError(
          kind: AuthUiKind.verificationCodeInvalid,
          title: 'Código incorrecto',
          message:
              'El código ingresado no es válido. Revisa el correo e inténtalo nuevamente.',
          action: 'Entendido',
          technicalCode: error.code,
        );
      case 'verification_code_expired':
        return AuthUiError(
          kind: AuthUiKind.verificationCodeExpired,
          title: 'Código expirado',
          message:
              'Este código ya no es válido. Solicita un nuevo código de verificación.',
          action: 'Enviar nuevo código',
          technicalCode: error.code,
        );
      case 'recovery_code_invalid':
        return AuthUiError(
          kind: AuthUiKind.resetCodeInvalid,
          title: 'Código incorrecto',
          message:
              'El código de recuperación no es válido. Verifica el código enviado a tu correo.',
          action: 'Entendido',
          technicalCode: error.code,
        );
      case 'recovery_code_expired':
        return AuthUiError(
          kind: AuthUiKind.resetCodeExpired,
          title: 'Código expirado',
          message:
              'El código de recuperación ya no es válido. Solicita uno nuevo.',
          action: 'Entendido',
          technicalCode: error.code,
        );
    }

    final status = error.statusCode;
    if (status == 429) {
      return AuthUiError(
        kind: AuthUiKind.tooManyAttempts,
        title: 'Demasiados intentos',
        message:
            'Has realizado demasiados intentos. Espera unos minutos y vuelve a intentarlo.',
        action: 'Entendido',
        technicalCode: error.code,
      );
    }

    final detail = _detail(error).toLowerCase();
    if (context == AuthErrorContext.register &&
        detail.contains('already exists')) {
      return AuthUiError(
        kind: AuthUiKind.emailAlreadyRegistered,
        title: 'Correo no disponible',
        message:
            'Este correo ya está registrado. Intenta iniciar sesión o recuperar tu contraseña.',
        action: 'Entendido',
        technicalCode: error.code,
      );
    }

    if (context == AuthErrorContext.passwordReset &&
        (error.code == 'validation_error' ||
            detail.contains('recovery token'))) {
      return AuthUiError(
        kind: AuthUiKind.resetCodeInvalid,
        title: 'Código incorrecto',
        message:
            'El código de recuperación no es válido o ya venció. Solicita uno nuevo.',
        action: 'Entendido',
        technicalCode: error.code,
      );
    }

    if (status != null && status >= 500 && status <= 599) {
      return AuthUiError(
        kind: AuthUiKind.server,
        title: 'Servicio temporalmente no disponible',
        message:
            'No pudimos completar la operación en este momento. '
            'Inténtalo nuevamente más tarde.',
        action: 'Entendido',
        technicalCode: error.code,
      );
    }

    return null;
  }

  static String _detail(ApiException error) {
    try {
      final decoded = jsonDecode(error.message);
      if (decoded is Map && decoded['detail'] != null) {
        return decoded['detail'].toString();
      }
    } catch (_) {}
    return error.message;
  }

  static bool _isNetwork(Object error) {
    if (error is TimeoutException || error is http.ClientException) {
      return true;
    }
    switch (error.runtimeType.toString()) {
      case 'SocketException':
      case 'HandshakeException':
      case 'TlsException':
      case 'HttpException':
        return true;
    }
    return false;
  }
}
