import 'package:flutter/material.dart';

import '../../../../core/theme/cuni_theme.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';

typedef RegisterSubmit = Future<void> Function({
  required String email,
  required String password,
});

class AuthRegisterScreen extends StatefulWidget {
  const AuthRegisterScreen({super.key, this.onSubmit});

  final RegisterSubmit? onSubmit;

  @override
  State<AuthRegisterScreen> createState() => _AuthRegisterScreenState();
}

class _AuthRegisterScreenState extends State<AuthRegisterScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  bool _pwVisible = false;
  bool _confirmVisible = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _email.text.trim().isNotEmpty &&
      _password.text.isNotEmpty &&
      _confirm.text.isNotEmpty &&
      !_busy;

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cuenta creada. Por favor verifica tu correo.'),
        ),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: _busy ? null : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_ios_new),
                        tooltip: 'Volver',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Icon(
                      Icons.person_add_alt_1,
                      size: 54,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Crear cuenta',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Crea tu cuenta para empezar',
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
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newPassword],
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Campo requerido';
                              }
                              if (v.length < 6) return 'Mínimo 6 caracteres';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          CustomTextField(
                            controller: _confirm,
                            label: 'Confirmar contraseña',
                            prefixIcon: Icons.lock_outline,
                            obscureText: !_confirmVisible,
                            suffixIcon: _confirmVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            onSuffixTap: () =>
                                setState(() => _confirmVisible = !_confirmVisible),
                            textInputAction: TextInputAction.done,
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Campo requerido';
                              }
                              if (v != _password.text) {
                                return 'Las contraseñas no coinciden';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 18),
                          CustomButton(
                            text: 'Crear cuenta',
                            onPressed: _submit,
                            loading: _busy,
                            enabled: _canSubmit,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '¿Ya tienes una cuenta? ',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: CuniTheme.placeholderGray,
                              ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => Navigator.of(context).pop(),
                          child: const Text('Iniciar sesión'),
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

