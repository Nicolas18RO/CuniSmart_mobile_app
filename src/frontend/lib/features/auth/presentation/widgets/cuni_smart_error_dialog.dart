import 'package:flutter/material.dart';

import '../../../../core/errors/auth_ui_error.dart';
import '../../../../core/theme/cuni_theme.dart';
import 'custom_button.dart';

Future<void> showCuniSmartErrorDialog(
  BuildContext context,
  AuthUiError error,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final label = '${error.title}. ${error.message}';
      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Semantics(
          key: const Key('cuniSmartErrorDialog'),
          container: true,
          explicitChildNodes: true,
          label: label,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 48,
                        color: CuniTheme.primaryGreen,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        error.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                              color: CuniTheme.darkGray,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        error.message,
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
                  label: error.action,
                  child: CustomButton(
                    text: error.action,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
