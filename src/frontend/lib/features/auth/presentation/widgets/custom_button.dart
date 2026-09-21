import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.enabled = true,
  });

  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final canPress = enabled && !loading && onPressed != null;

    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: canPress ? onPressed : null,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: loading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 10),
                  ],
                  Text(text),
                ],
              ),
      ),
    );
  }
}

