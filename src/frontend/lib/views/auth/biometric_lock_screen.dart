import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/auth_viewmodel.dart';

/// Session is already valid server-side; this only unlocks local UI (biometric / PIN).
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _autoTried = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoUnlock());
  }

  Future<void> _autoUnlock() async {
    if (_autoTried || !mounted) return;
    _autoTried = true;
    final ok = await context.read<AuthViewModel>().unlockWithBiometric();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _hint = 'No se pudo verificar. Pulsa Desbloquear o inicia sesión de nuevo.';
      });
    }
  }

  Future<void> _manualUnlock() async {
    setState(() => _hint = null);
    final ok = await context.read<AuthViewModel>().unlockWithBiometric();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _hint = 'Autenticación cancelada o fallida.';
      });
    }
  }

  Future<void> _useAnotherAccount() async {
    await context.read<AuthViewModel>().abandonSessionToLogin();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.lock_outline, size: 72, color: scheme.primary),
              const SizedBox(height: 24),
              Text(
                'CuniSmart bloqueado',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Confirma tu identidad en el dispositivo para continuar.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              if (_hint != null) ...[
                const SizedBox(height: 16),
                Text(
                  _hint!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error),
                ),
              ],
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _manualUnlock,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Desbloquear'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _useAnotherAccount,
                child: const Text('Usar otra cuenta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
