import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/api_exception.dart';
import '../../services/auth_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../widgets/auth_input.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  bool _dialogOpen = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _parseErrorMessage(Object e) {
    if (e is ApiException) {
      final body = e.message;
      try {
        final map = jsonDecode(body) as Map<String, dynamic>?;
        if (map != null && map['detail'] != null) {
          return map['detail'].toString();
        }
      } catch (_) {
        return body;
      }
      return body;
    }
    return e.toString();
  }

  Map<String, dynamic>? _parseApiErrorBody(Object e) {
    if (e is! ApiException) return null;
    try {
      final map = jsonDecode(e.message) as Map<String, dynamic>?;
      return map;
    } catch (_) {
      return null;
    }
  }

  Future<void> _showEmailNotVerifiedDialog() async {
    if (_dialogOpen) return;
    _dialogOpen = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool sending = false;
        return StatefulBuilder(
          builder: (ctx2, setState) {
            Future<void> resend2() async {
              if (sending) return;
              final email = _email.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(ctx2).showSnackBar(
                  const SnackBar(content: Text('Ingresa tu email primero.')),
                );
                return;
              }

              setState(() {
                sending = true;
              });
              try {
                await ctx2
                    .read<AuthService>()
                    .resendVerificationEmail(email: email);
                if (!ctx2.mounted) return;
                Navigator.of(ctx2).pop();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Verification email sent')),
                );
              } catch (e) {
                if (!ctx2.mounted) return;
                final msg = _parseErrorMessage(e);
                ScaffoldMessenger.of(ctx2).showSnackBar(
                  SnackBar(content: Text(msg ?? 'Request failed')),
                );
              } finally {
                if (ctx2.mounted) {
                  setState(() {
                    sending = false;
                  });
                }
              }
            }

            return AlertDialog(
              title: const Text('Email not verified'),
              content: const Text(
                'Please verify your email before logging in.',
              ),
              actions: [
                TextButton(
                  onPressed: sending
                      ? null
                      : () {
                          Navigator.of(ctx2).pop();
                        },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: sending ? null : resend2,
                  child: sending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Resend Email'),
                ),
              ],
            );
          },
        );
      },
    );

    _dialogOpen = false;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthViewModel>().loginWithPassword(
            email: _email.text,
            password: _password.text,
          );
    } catch (e) {
      final body = _parseApiErrorBody(e);
      final code = body?['code']?.toString();
      if (code == 'email_not_verified') {
        setState(() => _error = null);
        await _showEmailNotVerifiedDialog();
      } else {
        setState(() => _error = _parseErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRegister() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.pets, size: 64, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome Back',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 28),
                  AuthInput(
                    controller: _email,
                    label: 'Email',
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email requerido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AuthInput(
                    controller: _password,
                    label: 'Password',
                    obscureText: true,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Contraseña requerida';
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: scheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Login'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _busy ? null : _showEmailNotVerifiedDialog,
                    child: const Text('Resend verification email'),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _busy ? null : _openRegister,
                    child: const Text("Don't have an account? Register"),
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

