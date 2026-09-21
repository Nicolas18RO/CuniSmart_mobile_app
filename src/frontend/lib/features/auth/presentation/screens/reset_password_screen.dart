import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/auth_ui_error.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/cuni_theme.dart';
import '../../../../viewmodels/auth_viewmodel.dart';
import '../widgets/cuni_smart_error_dialog.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';

typedef PasswordResetConfirm = Future<void> Function({
  required String email,
  required String code,
  required String newPassword,
});

class AuthResetPasswordScreen extends StatefulWidget {
  const AuthResetPasswordScreen({
    super.key,
    required this.email,
    this.onConfirmReset,
  });

  final String email;
  final PasswordResetConfirm? onConfirmReset;

  @override
  State<AuthResetPasswordScreen> createState() => _AuthResetPasswordScreenState();
}

class _AuthResetPasswordScreenState extends State<AuthResetPasswordScreen> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _pwVisible = false;
  bool _confirmVisible = false;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _code.text.trim().length == 6 &&
      _password.text.isNotEmpty &&
      _confirm.text.isNotEmpty &&
      !_busy;

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    if (widget.onConfirmReset == null) return;

    setState(() => _busy = true);
    try {
      await widget.onConfirmReset!(
        email: widget.email,
        code: _code.text.trim(),
        newPassword: _password.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contraseña actualizada. Inicia sesión con la nueva.'),
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
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
      // Widget tests may pump Reset without a ViewModel.
    }
    return ErrorMapper.map(error, context: AuthErrorContext.passwordReset);
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    Icons.password,
                    size: 54,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nueva contraseña',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Introduce el código de 6 dígitos enviado a:',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: CuniTheme.placeholderGray,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.email,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Form(
                    key: _formKey,
                    onChanged: () => setState(() {}),
                    child: Column(
                      children: [
                        Semantics(
                          textField: true,
                          label: 'Código de recuperación de 6 dígitos',
                          child: TextFormField(
                            key: const Key('recoveryCodeField'),
                            controller: _code,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            textAlign: TextAlign.center,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            maxLength: 6,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            style: const TextStyle(
                              fontSize: 28,
                              letterSpacing: 10,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Código de 6 dígitos',
                              counterText: '',
                            ),
                            validator: (v) {
                              if (v == null || v.trim().length != 6) {
                                return 'Ingresa los 6 dígitos';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        CustomTextField(
                          controller: _password,
                          label: 'Nueva contraseña',
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
                            if (v.length < 8) return 'Mínimo 8 caracteres';
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
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Campo requerido';
                            }
                            if (v != _password.text) {
                              return 'Las contraseñas no coinciden';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        Semantics(
                          button: true,
                          label: 'Guardar nueva contraseña',
                          child: CustomButton(
                            text: 'Guardar contraseña',
                            onPressed: _submit,
                            loading: _busy,
                            enabled: _canSubmit,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
