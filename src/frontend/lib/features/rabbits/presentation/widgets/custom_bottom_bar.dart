import 'package:flutter/material.dart';

import '../../../../core/theme/cuni_theme.dart';

class BottomBarItem {
  const BottomBarItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class CustomBottomBar extends StatelessWidget {
  const CustomBottomBar({
    super.key,
    required this.items,
    required this.activeIndex,
    required this.onTap,
  });

  final List<BottomBarItem> items;
  final int activeIndex;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + safe),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: CuniTheme.borderGray),
        ),
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final item = items[i];
          final active = i == activeIndex;
          return Expanded(
            child: _BottomBarButton(
              item: item,
              active: active,
              onTap: onTap == null ? null : () => onTap!(i),
            ),
          );
        }),
      ),
    );
  }
}

class _BottomBarButton extends StatelessWidget {
  const _BottomBarButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final BottomBarItem item;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const activeBg = CuniTheme.rabbitsCardBackground;
    final iconColor =
        active ? CuniTheme.rabbitsPrimaryGreen : CuniTheme.rabbitsTextSecondary;
    final textColor =
        active ? CuniTheme.rabbitsTextPrimary : CuniTheme.rabbitsTextSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: active ? activeBg : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(item.icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              item.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

