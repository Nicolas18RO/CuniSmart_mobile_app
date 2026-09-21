import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/auth_ui_error.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/cuni_theme.dart';
import '../../../../viewmodels/auth_viewmodel.dart';
import '../widgets/cuni_smart_error_dialog.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import 'reset_password_screen.dart';

typedef PasswordResetRequest = Future<void> Function({required String email});

class AuthForgotPasswordScreen extends StatefulWidget {
  const AuthForgotPasswordScreen({
    super.key,
    this.onRequestReset,
    this.onConfirmReset,
  });

  final PasswordResetRequest? onRequestReset;
  final PasswordResetConfirm? onConfirmReset;

  @override
  State<AuthForgotPasswordScreen> createState() =>
      _AuthForgotPasswordScreenState();
}

class _AuthForgotPasswordScreenState extends State<AuthForgotPasswordScreen> {
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  bool get _canSubmit => _email.text.trim().isNotEmpty && !_busy;

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    if (widget.onRequestReset == null) return;

    setState(() => _busy = true);
    try {
      await widget.onRequestReset!(email: _email.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Si existe una cuenta, enviamos un mensaje de recuperación.',
          ),
        ),
      );
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AuthResetPasswordScreen(
            email: _email.text.trim(),
            onConfirmReset: widget.onConfirmReset,
          ),
        ),
      );
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
      // Widget tests may pump Forgot without a ViewModel.
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
                    Icons.lock_reset,
                    size: 54,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Recuperar contraseña',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Introduce tu correo. Si hay una cuenta, te enviaremos un código.',
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
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.email],
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Campo requerido';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        Semantics(
                          button: true,
                          label: 'Enviar código de recuperación',
                          child: CustomButton(
                            text: 'Enviar código',
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
