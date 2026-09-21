import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

import '../core/errors/auth_ui_error.dart';
import '../core/errors/error_mapper.dart';
import '../models/auth_bootstrap.dart';
import '../services/auth_service.dart';
import '../services/device_authenticator.dart';
import '../services/device_credential_contract.dart';
import '../services/device_credential_signer.dart';

enum AuthGate {
  /// Showing splash; running bootstrap.
  splash,

  /// Must show login (no valid session).
  login,

  /// Session valid; server allows biometric gate — unlock device before app.
  biometricLock,

  /// Main app (session OK, biometric passed or not required).
  app,
}

enum AuthSubmitStatus {
  idle,
  loading,
  success,
  error,
}

class AuthViewModel extends ChangeNotifier
    implements BiometricLoginViewModelApi {
  AuthViewModel({
    required AuthService authService,
    DeviceAuthenticator? deviceAuth,
    DeviceCredentialSigner? deviceSigner,
    DateTime Function()? clock,
  })  : _auth = authService,
        _device = deviceAuth ?? LocalDeviceAuthenticator(),
        _signer = deviceSigner ?? LocalDeviceCredentialSigner(),
        _clock = clock ?? DateTime.now {
    _auth.onSessionInvalid = _forceLogin;
    unawaited(_restoreEnrollmentFromStorage().then((_) {
      if (canOfferBiometricLogin) notifyListeners();
    }));
  }

  static const Duration inactivityLockTimeout = Duration(minutes: 15);

  final AuthService _auth;
  final DeviceAuthenticator _device;
  final DeviceCredentialSigner _signer;
  final DateTime Function() _clock;

  AuthGate _gate = AuthGate.splash;
  BootstrapResult? _lastBootstrap;
  bool _biometricEnabled = false;
  bool _biometricHardwareAvailable = false;
  bool _biometricBusy = false;
  String? _biometricError;
  AuthSubmitStatus _loginStatus = AuthSubmitStatus.idle;
  AuthUiError? _lastError;
  DateTime? _pausedAt;
  String? _sessionEmail;
  String? _deviceCredentialId;
  String? _enrolledUserHint;

  AuthGate get gate => _gate;
  BootstrapResult? get lastBootstrap => _lastBootstrap;
  bool get biometricEnabled => _biometricEnabled;
  bool get biometricHardwareAvailable => _biometricHardwareAvailable;
  bool get biometricBusy => _biometricBusy;
  String? get biometricError => _biometricError;
  AuthSubmitStatus get loginStatus => _loginStatus;
  AuthUiError? get lastError => _lastError;
  bool get isSubmitting => _loginStatus == AuthSubmitStatus.loading;

  @override
  bool get canOfferBiometricLogin =>
      _deviceCredentialId != null && _deviceCredentialId!.isNotEmpty;

  @override
  String? get enrolledUserHint => _enrolledUserHint;

  bool get _hasBiometricPreference =>
      _biometricEnabled || (_lastBootstrap?.biometricAvailable ?? false);

  /// Pause/resume. After [inactivityLockTimeout] with a live session and
  /// biometrics available, shows [AuthGate.biometricLock] without logging out.
  Future<void> handleAppLifecycle(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _pausedAt ??= _clock();
        return;
      case AppLifecycleState.resumed:
        await _lockIfInactive();
        _pausedAt = null;
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        return;
    }
  }

  Future<void> _lockIfInactive() async {
    if (_gate != AuthGate.app) return;
    final pausedAt = _pausedAt;
    if (pausedAt == null) return;
    if (_clock().difference(pausedAt) < inactivityLockTimeout) return;
    if (!_hasBiometricPreference) return;
    final can = await _device.canAuthenticate();
    _biometricHardwareAvailable = can;
    if (!can) return;
    _gate = AuthGate.biometricLock;
    notifyListeners();
  }

  /// Called from splash once. Never navigates to app without bootstrap result.
  Future<void> runBootstrap() async {
    if (_gate != AuthGate.splash) {
      _gate = AuthGate.splash;
      notifyListeners();
    }

    final result = await _auth.bootstrap();
    _lastBootstrap = result;

    if (!result.sessionValid) {
      _gate = AuthGate.login;
      notifyListeners();
      return;
    }

    if (result.biometricAvailable) {
      final canPrompt = await _device.canAuthenticate();
      _biometricHardwareAvailable = canPrompt;
      if (canPrompt) {
        _gate = AuthGate.biometricLock;
        notifyListeners();
        return;
      }
    }

    _gate = AuthGate.app;
    notifyListeners();
  }

  /// After password login — go straight to app (user already proved identity).
  Future<void> loginWithPassword({
    required String email,
    required String password,
  }) async {
    if (isSubmitting) return;
    _loginStatus = AuthSubmitStatus.loading;
    _lastError = null;
    notifyListeners();
    try {
      await _auth.login(email: email, password: password);
      _sessionEmail = email.trim();
      _gate = AuthGate.app;
      _loginStatus = AuthSubmitStatus.success;
      notifyListeners();
    } catch (e) {
      _lastError = ErrorMapper.map(e, context: AuthErrorContext.login);
      _loginStatus = AuthSubmitStatus.error;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> register({
    required String email,
    required String password,
  }) {
    return _runMapped(
      () => _auth.register(email: email, password: password),
      AuthErrorContext.register,
    );
  }

  Future<void> requestPasswordReset({required String email}) {
    return _runMapped(
      () => _auth.requestPasswordReset(email: email),
      AuthErrorContext.passwordReset,
    );
  }

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) {
    return _runMapped(
      () => _auth.confirmPasswordReset(
        email: email,
        code: code,
        newPassword: newPassword,
      ),
      AuthErrorContext.passwordReset,
    );
  }

  Future<void> resendVerificationEmail({required String email}) {
    return _runMapped(
      () => _auth.resendVerificationEmail(email: email),
      AuthErrorContext.resendVerification,
    );
  }

  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) {
    return _runMapped(
      () => _auth.verifyEmailCode(email: email, code: code),
      AuthErrorContext.emailVerification,
    );
  }

  Future<void> _runMapped(
    Future<void> Function() action,
    AuthErrorContext context,
  ) async {
    if (isSubmitting) return;
    _loginStatus = AuthSubmitStatus.loading;
    _lastError = null;
    notifyListeners();
    try {
      await action();
      _loginStatus = AuthSubmitStatus.success;
      notifyListeners();
    } catch (e) {
      _lastError = ErrorMapper.map(e, context: context);
      _loginStatus = AuthSubmitStatus.error;
      notifyListeners();
      rethrow;
    }
  }

  /// Device biometric / PIN — does not call backend; only unlocks UI after session exists.
  Future<bool> unlockWithBiometric() async {
    try {
      final ok = await _device.authenticate(
        reason: 'Desbloquea para acceder a CuniSmart',
      );
      if (!ok) return false;
      _gate = AuthGate.app;
      notifyListeners();
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<void> loadBiometricPreference() async {
    _biometricError = null;
    _biometricHardwareAvailable = await _device.canAuthenticate();
    try {
      _biometricEnabled = await _auth.fetchBiometricEnabled();
    } catch (e) {
      debugPrint('Biometric preference load error: $e');
      _biometricError = 'No se pudo leer la preferencia de desbloqueo.';
    }
    notifyListeners();
  }

  /// Opt-in/out. Enabling requires device capability + a successful local prompt.
  /// Only `{biometric_enabled}` is sent to the API.
  Future<bool> setBiometricEnabled(bool enabled) async {
    if (_biometricBusy) return false;
    _biometricBusy = true;
    _biometricError = null;
    notifyListeners();

    try {
      if (enabled) {
        final can = await _device.canAuthenticate();
        _biometricHardwareAvailable = can;
        if (!can) {
          _biometricError =
              'Este dispositivo no admite huella, rostro o PIN de bloqueo.';
          return false;
        }
        try {
          final verified = await _device.authenticate(
            reason: 'Confirma tu identidad para activar el desbloqueo',
          );
          if (!verified) {
            _biometricError =
                'No se pudo verificar tu identidad. Inténtalo nuevamente.';
            return false;
          }
        } on PlatformException catch (e) {
          _biometricError = _mapBiometricPlatformException(e);
          return false;
        }
      }

      await _auth.updateBiometricEnabled(enabled);
      _biometricEnabled = enabled;
      if (enabled) {
        try {
          await _persistDeviceCredential();
        } catch (_) {
          // El candado ya quedó guardado; el enrolamiento se puede reintentar.
        }
      }
      return true;
    } catch (e) {
      debugPrint('Biometric preference save error: $e');
      _biometricError = 'No se pudo guardar la preferencia.';
      return false;
    } finally {
      _biometricBusy = false;
      notifyListeners();
    }
  }

  /// Clear tokens and show login (e.g. user gives up on lock screen).
  Future<void> abandonSessionToLogin() async {
    await _auth.logout();
    await _restoreEnrollmentFromStorage();
    _forceLogin();
  }

  Future<void> logout() async {
    await _auth.logout();
    await _restoreEnrollmentFromStorage();
    _forceLogin();
  }

  Future<void> _restoreEnrollmentFromStorage() async {
    _deviceCredentialId = await _auth.readDeviceCredentialId();
    _enrolledUserHint = await _auth.readEnrolledUserHint();
  }

  @override
  Future<bool> enrollDeviceCredential() async {
    try {
      final verified = await _device.authenticate(
        reason: 'Confirma tu identidad para ingresar con huella',
      );
      if (!verified) return false;
      return _persistDeviceCredential();
    } on PlatformException {
      return false;
    } catch (e) {
      debugPrint('Device credential enroll error: $e');
      return false;
    }
  }

  Future<bool> _persistDeviceCredential() async {
    final publicKey = await _signer.exportPublicKey();
    final id = await _auth.enrollDeviceCredential(
      publicKey: publicKey,
      deviceLabel: 'CuniSmart',
    );
    final hint = _sessionEmail;
    await _auth.writeDeviceCredentialId(id);
    await _auth.writeEnrolledUserHint(hint);
    _deviceCredentialId = id;
    _enrolledUserHint = hint;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> loginWithBiometric() async {
    await _restoreEnrollmentFromStorage();
    final credentialId = _deviceCredentialId;
    if (credentialId == null || credentialId.isEmpty) return false;
    try {
      final verified = await _device.authenticate(
        reason: 'Ingresa con tu huella o el método biométrico del dispositivo',
      );
      if (!verified) return false;
      final challenge = await _auth.requestDeviceChallenge(
        credentialId: credentialId,
      );
      final signature = await _signer.sign(challenge.nonce);
      await _auth.loginWithDeviceCredential(
        credentialId: credentialId,
        nonce: challenge.nonce,
        signature: signature,
      );
      _gate = AuthGate.app;
      _loginStatus = AuthSubmitStatus.success;
      notifyListeners();
      return true;
    } on PlatformException {
      return false;
    } catch (e) {
      debugPrint('Biometric login error: $e');
      _lastError = ErrorMapper.map(e, context: AuthErrorContext.login);
      notifyListeners();
      return false;
    }
  }

  void _forceLogin() {
    if (_gate == AuthGate.login) return;
    _gate = AuthGate.login;
    notifyListeners();
  }

  String _mapBiometricPlatformException(PlatformException error) {
    if (error.code == auth_error.lockedOut ||
        error.code == auth_error.permanentlyLockedOut) {
      return 'La autenticación biométrica está temporalmente bloqueada. '
          'Intenta nuevamente más tarde.';
    }
    return 'No fue posible activar la autenticación biométrica. '
        'Inténtalo nuevamente.';
  }
}
