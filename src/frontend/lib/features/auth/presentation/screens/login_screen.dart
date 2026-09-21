import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/auth_ui_error.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/cuni_theme.dart';
import '../../../../viewmodels/auth_viewmodel.dart';
import '../widgets/cuni_smart_error_dialog.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import 'register_screen.dart';
import 'verify_email_screen.dart';

typedef LoginSubmit = Future<void> Function({
  required String email,
  required String password,
});

typedef ResendVerification = Future<void> Function({required String email});

class AuthLoginScreen extends StatefulWidget {
  const AuthLoginScreen({
    super.key,
    this.onSubmit,
    this.onRegisterSubmit,
    this.onForgotPassword,
    this.onResendVerification,
    this.onVerifyEmail,
  });

  final LoginSubmit? onSubmit;
  final RegisterSubmit? onRegisterSubmit;
  final VoidCallback? onForgotPassword;
  final ResendVerification? onResendVerification;
  final VerifyEmailSubmit? onVerifyEmail;

  @override
  State<AuthLoginScreen> createState() => _AuthLoginScreenState();
}

class _AuthLoginScreenState extends State<AuthLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  bool _pwVisible = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _email.text.trim().isNotEmpty && _password.text.isNotEmpty && !_busy;

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    if (widget.onSubmit == null) return;

    setState(() => _busy = true);
    try {
      await widget.onSubmit!(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        // optional: if embedded in a flow, pop.
      }
    } catch (e) {
      if (!mounted) return;
      final ui = _resolveUiError(e);
      setState(() => _busy = false);
      if (ui.kind == AuthUiKind.emailNotVerified) {
        await _openVerifyEmail();
      } else {
        await showCuniSmartErrorDialog(context, ui);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _biometricLoginActions(BuildContext context) {
    AuthViewModel? vm;
    try {
      vm = context.watch<AuthViewModel>();
    } on ProviderNotFoundException {
      return const [];
    }
    if (!vm.canOfferBiometricLogin) return const [];
    final hint = vm.enrolledUserHint;
    final label = (hint == null || hint.isEmpty)
        ? 'Ingresar con huella'
        : 'Ingresar con huella. Continuar como $hint';
    final authVm = vm;
    return [
      const SizedBox(height: 12),
      Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: CustomButton(
          text: 'Ingresar con huella',
          icon: Icons.fingerprint,
          onPressed: _busy ? null : () => _submitBiometric(authVm),
          enabled: !_busy,
        ),
      ),
    ];
  }

  Future<void> _submitBiometric(AuthViewModel vm) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await vm.loginWithBiometric();
      if (!mounted) return;
      if (!ok && vm.lastError != null) {
        await showCuniSmartErrorDialog(context, vm.lastError!);
      }
    } catch (e) {
      if (!mounted) return;
      await showCuniSmartErrorDialog(context, _resolveUiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  AuthUiError _resolveUiError(Object error) {
    try {
      final mapped = context.read<AuthViewModel>().lastError;
      if (mapped != null) return mapped;
    } on ProviderNotFoundException {
      // Widget tests may pump Login without a ViewModel.
    }
    return ErrorMapper.map(error);
  }

  Future<void> _openRegister() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuthRegisterScreen(
          onSubmit: widget.onRegisterSubmit,
          onVerifyEmail: widget.onVerifyEmail,
          onResendVerification: widget.onResendVerification,
        ),
      ),
    );
  }

  Future<void> _openVerifyEmail() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa tu correo primero.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuthVerifyEmailScreen(
          email: email,
          onVerify: widget.onVerifyEmail,
          onResend: widget.onResendVerification,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final maxWidth = w < 520 ? w : 520.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 28),
                    const _BrandHeader(),
                    const SizedBox(height: 32),
                    Text(
                      'Bienvenido de nuevo',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Inicia sesión para continuar',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: CuniTheme.placeholderGray,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    Form(
                      key: _formKey,
                      onChanged: () => setState(() {}),
                      child: Column(
                        children: [
                          CustomTextField(
                            controller: _email,
                            label: 'Correo electrónico',
                            hint: 'tu@email.com',
                            prefixIcon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Campo requerido';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          CustomTextField(
                            controller: _password,
                            label: 'Contraseña',
                            prefixIcon: Icons.lock_outline,
                            obscureText: !_pwVisible,
                            suffixIcon: _pwVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            onSuffixTap: () =>
                                setState(() => _pwVisible = !_pwVisible),
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _submit(),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Campo requerido';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                          Align(
                            alignment: Alignment.center,
                            child: IntrinsicWidth(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  CustomButton(
                                    text: 'Iniciar sesión',
                                    onPressed: _submit,
                                    loading: _busy,
                                    enabled: _canSubmit,
                                  ),
                                  ..._biometricLoginActions(context),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Semantics(
                              button: true,
                              label: 'Olvidaste tu contraseña',
                              child: TextButton(
                                onPressed:
                                    _busy ? null : widget.onForgotPassword,
                                child: const Text('¿Olvidaste tu contraseña?'),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Semantics(
                              button: true,
                              label: 'Reenviar correo de verificación',
                              child: TextButton(
                                onPressed: _busy ? null : _openVerifyEmail,
                                child: const Text(
                                  'Reenviar correo de verificación',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "¿No tienes una cuenta? ",
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: CuniTheme.placeholderGray,
                                  ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _openRegister,
                          child: const Text('Registrarse'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.pets,
            size: 54, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        RichText(
          text: const TextSpan(
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            children: [
              TextSpan(
                  text: 'Cuni', style: TextStyle(color: CuniTheme.darkGray)),
              TextSpan(
                text: 'Smart',
                style: TextStyle(color: CuniTheme.primaryGreen),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
