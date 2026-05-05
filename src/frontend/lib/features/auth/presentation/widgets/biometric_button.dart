import 'package:flutter/material.dart';

import '../../../../core/theme/cuni_theme.dart';

class BiometricButton extends StatelessWidget {
  const BiometricButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          width: 56,
          decoration: BoxDecoration(
            color: CuniTheme.lightGrayBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: CuniTheme.borderGray),
          ),
          child: Icon(
            icon,
            color: enabled ? scheme.primary : scheme.onSurface.withOpacity(0.38),
          ),
        ),
      ),
    );
  }
}

