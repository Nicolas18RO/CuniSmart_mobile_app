import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import '../models/auth_bootstrap.dart';
import '../services/auth_service.dart';

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

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({
    required AuthService authService,
    LocalAuthentication? localAuth,
  })  : _auth = authService,
        _localAuth = localAuth ?? LocalAuthentication();

  final AuthService _auth;
  final LocalAuthentication _localAuth;

  AuthGate _gate = AuthGate.splash;
  BootstrapResult? _lastBootstrap;

  AuthGate get gate => _gate;
  BootstrapResult? get lastBootstrap => _lastBootstrap;

  /// Called from splash once. Never navigates to app without bootstrap result.
  Future<void> runBootstrap() async {
    _gate = AuthGate.splash;
    notifyListeners();

    final result = await _auth.bootstrap();
    _lastBootstrap = result;

    if (!result.sessionValid) {
      _gate = AuthGate.login;
      notifyListeners();
      return;
    }

    if (result.biometricAvailable) {
      final canPrompt = await _deviceCanAuthenticate();
      if (canPrompt) {
        _gate = AuthGate.biometricLock;
        notifyListeners();
        return;
      }
    }

    _gate = AuthGate.app;
    notifyListeners();
  }

  Future<bool> _deviceCanAuthenticate() async {
    try {
      return await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// After password login — go straight to app (user already proved identity).
  Future<void> loginWithPassword({
    required String email,
    required String password,
  }) async {
    await _auth.login(email: email, password: password);
    _gate = AuthGate.app;
    notifyListeners();
  }

  /// Device biometric / PIN — does not call backend; only unlocks UI after session exists.
  Future<bool> unlockWithBiometric() async {
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Desbloquea para acceder a CuniSmart',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (!ok) return false;
      _gate = AuthGate.app;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Biometric auth error: $e');
      return false;
    }
  }

  /// Clear tokens and show login (e.g. user gives up on lock screen).
  Future<void> abandonSessionToLogin() async {
    await _auth.clearSession();
    _gate = AuthGate.login;
    notifyListeners();
  }

  Future<void> logout() async {
    await _auth.clearSession();
    _gate = AuthGate.login;
    notifyListeners();
  }
}
