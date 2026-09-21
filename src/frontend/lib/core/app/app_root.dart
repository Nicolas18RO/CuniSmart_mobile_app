import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
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

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  late final Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrapFuture = context.read<AuthViewModel>().runBootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    context.read<AuthViewModel>().handleAppLifecycle(state);
  }

  Future<void> _register({
    required String email,
    required String password,
  }) {
    return context.read<AuthViewModel>().register(
          email: email,
          password: password,
        );
  }

  Future<void> _login({
    required String email,
    required String password,
  }) {
    return context.read<AuthViewModel>().loginWithPassword(
          email: email,
          password: password,
        );
  }

  Future<void> _requestPasswordReset({required String email}) {
    return context.read<AuthViewModel>().requestPasswordReset(email: email);
  }

  Future<void> _confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) {
    return context.read<AuthViewModel>().confirmPasswordReset(
          email: email,
          code: code,
          newPassword: newPassword,
        );
  }

  Future<void> _resendVerification({required String email}) {
    return context.read<AuthViewModel>().resendVerificationEmail(email: email);
  }

  Future<void> _verifyEmailCode({
    required String email,
    required String code,
  }) {
    return context.read<AuthViewModel>().verifyEmailCode(
          email: email,
          code: code,
        );
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuthForgotPasswordScreen(
          onRequestReset: _requestPasswordReset,
          onConfirmReset: _confirmPasswordReset,
        ),
      ),
    );
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
          onForgotPassword: _openForgotPassword,
          onResendVerification: _resendVerification,
          onVerifyEmail: _verifyEmailCode,
        );
      },
    );
  }
}
