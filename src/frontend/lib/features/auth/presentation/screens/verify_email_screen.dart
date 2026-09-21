import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/auth_ui_error.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/cuni_theme.dart';
import '../../../../viewmodels/auth_viewmodel.dart';
import '../widgets/cuni_smart_error_dialog.dart';
import '../widgets/custom_button.dart';

typedef VerifyEmailSubmit = Future<void> Function({
  required String email,
  required String code,
});

typedef ResendVerificationCode = Future<void> Function({required String email});

class AuthVerifyEmailScreen extends StatefulWidget {
  const AuthVerifyEmailScreen({
    super.key,
    required this.email,
    this.onVerify,
    this.onResend,
    this.resendCooldown = const Duration(seconds: 60),
  });

  final String email;
  final VerifyEmailSubmit? onVerify;
  final ResendVerificationCode? onResend;
  final Duration resendCooldown;

  @override
  State<AuthVerifyEmailScreen> createState() => _AuthVerifyEmailScreenState();
}

class _AuthVerifyEmailScreenState extends State<AuthVerifyEmailScreen> {
  final _code = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _cooldownSeconds = widget.resendCooldown.inSeconds;
    if (_cooldownSeconds > 0) {
      _cooldownTimer = Timer.periodic(
        const Duration(seconds: 1),
        _onCooldownTick,
      );
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _code.dispose();
    super.dispose();
  }

  bool get _canSubmit => _code.text.trim().length == 6 && !_busy;

  bool get _canResend =>
      !_busy && _cooldownSeconds <= 0 && widget.onResend != null;

  void _onCooldownTick(Timer timer) {
    if (!mounted) {
      timer.cancel();
      return;
    }
    setState(() {
      _cooldownSeconds -= 1;
      if (_cooldownSeconds <= 0) {
        _cooldownSeconds = 0;
        timer.cancel();
      }
    });
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    final seconds = widget.resendCooldown.inSeconds;
    setState(() => _cooldownSeconds = seconds);
    if (seconds <= 0) return;
    _cooldownTimer = Timer.periodic(
      const Duration(seconds: 1),
      _onCooldownTick,
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (widget.onVerify == null) return;

    setState(() => _busy = true);
    try {
      await widget.onVerify!(
        email: widget.email,
        code: _code.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Correo verificado. Ya puedes iniciar sesión.'),
        ),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await showCuniSmartErrorDialog(context, _resolveUiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (!_canResend) return;
    setState(() => _busy = true);
    try {
      await widget.onResend!(email: widget.email);
      if (!mounted) return;
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Si la cuenta existe y falta verificar, enviamos un correo.',
          ),
        ),
      );
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
      // Widget tests may pump the screen without a ViewModel.
    }
    return ErrorMapper.map(error, context: AuthErrorContext.emailVerification);
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final maxWidth = w < 520 ? w : 520.0;
    final cooldownHint = _cooldownSeconds > 0
        ? 'Puedes reenviar en $_cooldownSeconds s'
        : '¿No recibiste el código?';

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
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed:
                          _busy ? null : () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_ios_new),
                      tooltip: 'Volver',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Icon(
                    Icons.mark_email_read_outlined,
                    size: 54,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Verifica tu correo',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enviamos un código de 6 dígitos a:',
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
                  const SizedBox(height: 8),
                  Text(
                    'Ingresa el código para activar tu cuenta.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: CuniTheme.placeholderGray,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Form(
                    key: _formKey,
                    onChanged: () => setState(() {}),
                    child: Semantics(
                      textField: true,
                      label: 'Código de verificación de 6 dígitos',
                      child: TextFormField(
                        key: const Key('verificationCodeField'),
                        controller: _code,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
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
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  CustomButton(
                    text: 'Verificar',
                    onPressed: _submit,
                    loading: _busy,
                    enabled: _canSubmit,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    cooldownHint,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: CuniTheme.placeholderGray,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  Semantics(
                    button: true,
                    label: 'Reenviar código',
                    child: TextButton(
                      onPressed: _canResend ? _resend : null,
                      child: const Text('Reenviar código'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
