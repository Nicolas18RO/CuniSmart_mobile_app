import 'package:flutter/material.dart';

import '../../../../core/theme/cuni_theme.dart';
import 'custom_button.dart';

const biometricActivationTitle = 'Activar autenticación biométrica';
const biometricActivationMessage =
    'Al activar esta opción, al abrir la aplicación se te pedirá tu huella '
    'o el método biométrico configurado en tu dispositivo.';

/// Confirmation before the system biometric prompt. Cancel does not enable.
Future<bool> showBiometricActivationDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Semantics(
          key: const Key('biometricActivationDialog'),
          container: true,
          explicitChildNodes: true,
          label: '$biometricActivationTitle. $biometricActivationMessage',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.fingerprint,
                        size: 48,
                        color: CuniTheme.primaryGreen,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        biometricActivationTitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                              color: CuniTheme.darkGray,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        biometricActivationMessage,
                        textAlign: TextAlign.center,
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              color: CuniTheme.darkGray,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Semantics(
                  button: true,
                  label: 'Continuar',
                  child: CustomButton(
                    text: 'Continuar',
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  button: true,
                  label: 'Cancelar',
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancelar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result == true;
}
