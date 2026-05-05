import 'package:flutter/material.dart';

import '../../../../core/theme/cuni_theme.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import 'register_screen.dart';

typedef LoginSubmit = Future<void> Function({
  required String email,
  required String password,
});

class AuthLoginScreen extends StatefulWidget {
  const AuthLoginScreen({
    super.key,
    this.onSubmit,
    this.onRegisterSubmit,
    this.onForgotPassword,
  });

  final LoginSubmit? onSubmit;
  final RegisterSubmit? onRegisterSubmit;
  final VoidCallback? onForgotPassword;

  @override
  State<AuthLoginScreen> createState() => _AuthLoginScreenState();
}

class _AuthLoginScreenState extends State<AuthLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  bool _pwVisible = false;
  String? _error;

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
      setState(() => _error = null);
      if (Navigator.of(context).canPop()) {
        // optional: if embedded in a flow, pop.
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRegister() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuthRegisterScreen(onSubmit: widget.onRegisterSubmit),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                            suffixIcon:
                                _pwVisible ? Icons.visibility_off : Icons.visibility,
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
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _error!,
                                style: TextStyle(color: scheme.error),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          CustomButton(
                            text: 'Iniciar sesión',
                            onPressed: _submit,
                            loading: _busy,
                            enabled: _canSubmit,
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy ? null : widget.onForgotPassword,
                              child: const Text('¿Olvidaste tu contraseña?'),
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
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
        Icon(Icons.pets, size: 54, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        RichText(
          text: const TextSpan(
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            children: [
              TextSpan(text: 'Cuni', style: TextStyle(color: CuniTheme.darkGray)),
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

