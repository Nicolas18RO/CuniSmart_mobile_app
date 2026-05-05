import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/api_exception.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../services/auth_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../views/auth/biometric_lock_screen.dart';

/// Root that runs bootstrap once and then shows Home or Auth.
///
/// It does NOT bypass AuthService/AuthViewModel logic; it only orchestrates screens.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.home});

  /// The real app home (rabbits panel / main shell).
  final Widget home;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late final Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = context.read<AuthViewModel>().runBootstrap();
  }

  String? _parseBackendDetail(Object e) {
    if (e is ApiException) {
      try {
        final map = jsonDecode(e.message) as Map<String, dynamic>?;
        if (map != null && map['detail'] != null) {
          return map['detail'].toString();
        }
      } catch (_) {
        return e.message;
      }
      return e.message;
    }
    return e.toString();
  }

  Future<void> _register({
    required String email,
    required String password,
  }) async {
    try {
      await context.read<AuthService>().register(email: email, password: password);
    } catch (e) {
      if (!mounted) return;
      final msg = _parseBackendDetail(e) ?? 'Request failed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      rethrow;
    }
  }

  Future<void> _login({
    required String email,
    required String password,
  }) async {
    try {
      await context.read<AuthViewModel>().loginWithPassword(
            email: email,
            password: password,
          );
    } catch (e) {
      if (!mounted) return;
      final msg = _parseBackendDetail(e) ?? 'Login failed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        final auth = context.watch<AuthViewModel>();

        if (snapshot.connectionState != ConnectionState.done ||
            auth.gate == AuthGate.splash) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (auth.gate == AuthGate.app) {
          return widget.home;
        }

        if (auth.gate == AuthGate.biometricLock) {
          return const BiometricLockScreen();
        }

        return AuthLoginScreen(
          onSubmit: _login,
          onRegisterSubmit: _register,
          onForgotPassword: null,
        );
      },
    );
  }
}

