import 'package:flutter/material.dart';

class VoiceListeningOverlay extends StatefulWidget {
  const VoiceListeningOverlay({super.key});

  @override
  State<VoiceListeningOverlay> createState() => _VoiceListeningOverlayState();
}

class _VoiceListeningOverlayState extends State<VoiceListeningOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_c.value);
              final scale = 1.0 + (t * 0.06);
              final opacity = 0.80 + (t * 0.20);

              return Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withOpacity(0.90),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: scheme.outlineVariant.withOpacity(0.7),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mic, color: scheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Escuchando…',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

