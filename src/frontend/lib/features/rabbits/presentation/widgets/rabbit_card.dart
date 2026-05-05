import 'package:flutter/material.dart';

import '../../../../core/theme/cuni_theme.dart';
import '../../../../models/rabbit.dart';

class RabbitCard extends StatelessWidget {
  const RabbitCard({
    super.key,
    required this.rabbit,
    required this.onEdit,
    required this.onDelete,
  });

  final Rabbit rabbit;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = MediaQuery.sizeOf(context).width;

    final pad = w < 380 ? 14.0 : 16.0;

    return Container(
      decoration: BoxDecoration(
        color: CuniTheme.rabbitsCardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: CuniTheme.borderGray),
      ),
      padding: EdgeInsets.all(pad),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rabbit.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: CuniTheme.rabbitsTextPrimary,
                      ),
                ),
              ),
              _IconAction(
                icon: Icons.edit_outlined,
                color: scheme.primary,
                onPressed: onEdit,
                tooltip: 'Editar',
              ),
              const SizedBox(width: 6),
              _IconAction(
                icon: Icons.delete_outline,
                color: CuniTheme.rabbitsDelete,
                onPressed: onDelete,
                tooltip: 'Eliminar',
              ),
            ],
          ),
          const SizedBox(height: 10),
          _KeyValueRow(label: 'Raza', value: rabbit.breed),
          const SizedBox(height: 8),
          _KeyValueRow(label: 'Estado', value: rabbit.status),
          const SizedBox(height: 8),
          _KeyValueRow(
            label: 'Peso',
            value: rabbit.weight == null
                ? '—'
                : '${rabbit.weight!.toStringAsFixed(1)} kg',
          ),
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: CuniTheme.rabbitsTextSecondary,
          fontWeight: FontWeight.w600,
        );
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: CuniTheme.rabbitsTextPrimary,
          fontWeight: FontWeight.w700,
        );

    return Row(
      children: [
        Expanded(child: Text(label, style: labelStyle)),
        const SizedBox(width: 12),
        Text(value, style: valueStyle),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.color,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}

