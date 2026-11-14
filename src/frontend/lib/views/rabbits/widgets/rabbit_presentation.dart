import 'package:flutter/material.dart';

import '../../../core/theme/cuni_theme.dart';
import '../../../models/rabbit.dart';

String rabbitStatusLabel(String status) {
  return switch (status) {
    'active' => 'Activo',
    'sold' => 'Vendido',
    'deceased' => 'Fallecido',
    _ => status,
  };
}

String rabbitSexLabel(String sex) {
  return switch (sex) {
    'male' => 'Macho',
    'female' => 'Hembra',
    _ => sex,
  };
}

String rabbitWeightLabel(Rabbit r) {
  if (r.weight == null) return 'Sin peso';
  return '${r.weight!.toStringAsFixed(1)} kg';
}

/// Colores de chip de estado (única fuente para lista y detalle).
class RabbitStatusColors {
  const RabbitStatusColors({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}

/// Paleta semántica: activo=verde, vendido=azul, fallecido=gris (no rojo).
RabbitStatusColors rabbitStatusColors(String status) {
  return switch (status) {
    'active' => const RabbitStatusColors(
        background: Color(0xFFDDEBD8),
        foreground: Color(0xFF2F5D32),
      ),
    'sold' => const RabbitStatusColors(
        background: Color(0xFFD6E4F0),
        foreground: Color(0xFF1E3A5F),
      ),
    'deceased' => const RabbitStatusColors(
        background: Color(0xFFE8EAED),
        foreground: Color(0xFF3C4043),
      ),
    _ => const RabbitStatusColors(
        background: CuniTheme.lightGrayBackground,
        foreground: CuniTheme.darkGray,
      ),
  };
}

/// Avatar/placeholder de presentación (sin backend de imágenes).
class RabbitAvatar extends StatelessWidget {
  const RabbitAvatar({
    super.key,
    required this.name,
    this.radius = 24,
  });

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      key: ValueKey('rabbit-list-avatar-$name'),
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Icon(Icons.pets, size: radius * 1.05),
    );
  }
}

/// Avatar de detalle (key distinto para contratos G5).
class RabbitDetailAvatar extends StatelessWidget {
  const RabbitDetailAvatar({
    super.key,
    required this.name,
    this.radius = 48,
  });

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      key: ValueKey('rabbit-detail-avatar-$name'),
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Icon(Icons.pets, size: radius * 0.9),
    );
  }
}

/// Chip de estado (texto + color; TalkBack no depende solo del color).
class RabbitStatusChip extends StatelessWidget {
  const RabbitStatusChip({
    super.key,
    required this.status,
    this.compact = false,
    this.semanticsLabel,
    this.excludeFromSemantics = false,
  });

  final String status;
  final bool compact;
  final String? semanticsLabel;
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) {
    final label = rabbitStatusLabel(status);
    final colors = rabbitStatusColors(status);

    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.foreground,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 12 : 13,
        ),
      ),
    );

    if (excludeFromSemantics) {
      return ExcludeSemantics(child: chip);
    }

    return Semantics(
      label: semanticsLabel ?? 'Estado: ${label.toLowerCase()}',
      excludeSemantics: true,
      child: chip,
    );
  }
}
