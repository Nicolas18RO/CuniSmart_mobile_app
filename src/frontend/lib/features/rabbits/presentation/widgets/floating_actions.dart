import 'package:flutter/material.dart';

import '../../../../core/theme/cuni_theme.dart';

class FloatingActions extends StatelessWidget {
  const FloatingActions({
    super.key,
    required this.onMic,
    required this.onAdd,
    this.isListening = false,
    this.isProcessing = false,
  });

  final VoidCallback? onMic;
  final VoidCallback? onAdd;
  final bool isListening;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context).bottom;

    return Positioned(
      right: 16,
      bottom: 74 + safe,
      child: Column(
        children: [
          _MiniCircle(
            icon: Icons.mic,
            onPressed: onMic,
            active: isListening || isProcessing,
          ),
          const SizedBox(height: 12),
          _PrimarySquare(
            icon: Icons.add,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _MiniCircle extends StatelessWidget {
  const _MiniCircle({
    required this.icon,
    required this.onPressed,
    required this.active,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: active
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: CuniTheme.rabbitsPrimaryGreen,
                ),
              )
            : Icon(icon, color: CuniTheme.rabbitsTextPrimary),
        tooltip: 'Voz',
      ),
    );
  }
}

class _PrimarySquare extends StatelessWidget {
  const _PrimarySquare({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CuniTheme.rabbitsPrimaryGreen,
      elevation: 3,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 56,
          width: 56,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

