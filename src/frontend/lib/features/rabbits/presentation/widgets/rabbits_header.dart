import 'package:flutter/material.dart';

import '../../../../core/theme/cuni_theme.dart';

class RabbitsHeader extends StatelessWidget {
  const RabbitsHeader({
    super.key,
    required this.title,
    this.onProfile,
    required this.onChat,
    required this.onRefresh,
  });

  final String title;
  final VoidCallback? onProfile;
  final VoidCallback? onChat;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final maxWidth = w < 680 ? w : 680.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Row(
            children: [
              _RoundIcon(
                icon: Icons.person_outline,
                onPressed: onProfile,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: CuniTheme.rabbitsTextPrimary,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              _RoundIcon(
                icon: Icons.chat_bubble_outline,
                onPressed: onChat,
              ),
              const SizedBox(width: 10),
              _RoundIcon(
                icon: Icons.refresh,
                onPressed: onRefresh,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: CuniTheme.rabbitsCardBackground,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 44,
          width: 44,
          child: Icon(
            icon,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}

