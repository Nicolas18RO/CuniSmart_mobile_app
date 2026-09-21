import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/cuni_theme.dart';
import '../../../../viewmodels/auth_viewmodel.dart';
import '../widgets/biometric_activation_dialog.dart';

class AuthSecuritySettingsScreen extends StatefulWidget {
  const AuthSecuritySettingsScreen({super.key});

  @override
  State<AuthSecuritySettingsScreen> createState() =>
      _AuthSecuritySettingsScreenState();
}

class _AuthSecuritySettingsScreenState extends State<AuthSecuritySettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthViewModel>().loadBiometricPreference();
    });
  }

  Future<void> _onToggle(bool enabled) async {
    final vm = context.read<AuthViewModel>();
    if (!enabled) {
      await vm.setBiometricEnabled(false);
      return;
    }
    final confirmed = await showBiometricActivationDialog(context);
    if (!confirmed || !mounted) return;
    await vm.setBiometricEnabled(true);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    final hardware = vm.biometricHardwareAvailable;
    final subtitle = !hardware
        ? 'No disponible en este dispositivo.'
        : 'Al abrir la app se pedirá huella, rostro o el PIN del teléfono.';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Seguridad'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Text(
            'Desbloqueo',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'La huella o el rostro nunca se envían al servidor. Solo se guarda si quieres el bloqueo al abrir la app.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: CuniTheme.placeholderGray,
                ),
          ),
          const SizedBox(height: 16),
          Semantics(
            label: 'Desbloqueo biométrico',
            toggled: vm.biometricEnabled,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Desbloqueo biométrico'),
              subtitle: Text(subtitle),
              value: vm.biometricEnabled,
              onChanged: vm.biometricBusy ? null : _onToggle,
            ),
          ),
          if (vm.biometricError != null) ...[
            const SizedBox(height: 8),
            Text(
              vm.biometricError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
