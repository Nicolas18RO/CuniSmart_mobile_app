import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import '../../core/state/submit_state.dart';
import '../../models/rabbit.dart';
import '../../models/sync_status.dart';
import '../../viewmodels/rabbit_viewmodel.dart';
import '../../viewmodels/voice_viewmodel.dart';
import 'rabbit_create_route.dart';
import 'rabbit_qr_view.dart';

class RabbitDetailView extends StatefulWidget {
  const RabbitDetailView({
    super.key,
    required this.rabbit,
    this.announceOnOpen = false,
  });

  final Rabbit rabbit;
  final bool announceOnOpen;

  static String sexLabel(String sex) {
    return switch (sex) {
      'male' => 'Macho',
      'female' => 'Hembra',
      _ => sex,
    };
  }

  static String statusLabel(String status) {
    return switch (status) {
      'active' => 'Activo',
      'sold' => 'Vendido',
      'deceased' => 'Fallecido',
      _ => status,
    };
  }

  @override
  State<RabbitDetailView> createState() => _RabbitDetailViewState();
}

class _RabbitDetailViewState extends State<RabbitDetailView> {
  late Rabbit _rabbit;

  @override
  void initState() {
    super.initState();
    _rabbit = widget.rabbit;
    if (widget.announceOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          context.read<VoiceViewModel>().announceFicha(_rabbit);
        } catch (_) {}
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RabbitViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final r = _rabbit;
    final inConflict = r.syncStatus == RabbitSyncStatus.conflict;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          r.name,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code),
            tooltip: 'Ver código QR',
            constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RabbitQrView(rabbit: r),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (inConflict) ...[
              Semantics(
                liveRegion: true,
                label:
                    'Este conejo se modificó en otro lugar. Elige qué versión conservar.',
                child: Material(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Este conejo se modificó en otro lugar. Elige qué versión conservar.',
                      style: textTheme.bodyLarge?.copyWith(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            _FichaRow(label: 'Nombre', value: r.name, order: 1),
            _FichaRow(label: 'Raza', value: r.breed, order: 2),
            _FichaRow(
              label: 'Sexo',
              value: RabbitDetailView.sexLabel(r.sex),
              order: 3,
            ),
            _FichaRow(
              label: 'Fecha de nacimiento',
              value: r.birthDate,
              order: 4,
            ),
            _FichaRow(
              label: 'Peso',
              value: r.weight == null
                  ? 'Sin peso'
                  : '${r.weight!.toStringAsFixed(1)} kg',
              order: 5,
            ),
            _FichaRow(
              label: 'Estado',
              value: RabbitDetailView.statusLabel(r.status),
              order: 6,
            ),
            _FichaRow(
              label: 'Observaciones',
              value: r.notes.trim().isEmpty ? 'Sin notas' : r.notes,
              order: 7,
            ),
            _FichaRow(label: 'Identificador', value: r.uuid, order: 8),
            _FichaRow(
              label: 'Sincronización',
              value: r.syncStatus.label,
              order: 9,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: Semantics(
                sortKey: const OrdinalSortKey(10),
                button: true,
                label: 'Ver código QR',
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RabbitQrView(rabbit: r),
                      ),
                    );
                  },
                  icon: const Icon(Icons.qr_code),
                  label: const Text('Ver código QR'),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: inConflict
                ? [
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: Semantics(
                        button: true,
                        label: 'Conservar versión del servidor',
                        child: FilledButton.icon(
                          onPressed: vm.isSubmitting
                              ? null
                              : () => _resolve(
                                    context,
                                    vm,
                                    keepRemote: true,
                                  ),
                          icon: const Icon(Icons.cloud_download_outlined),
                          label: const Text('Conservar versión del servidor'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: Semantics(
                        button: true,
                        label: 'Conservar mis cambios',
                        child: OutlinedButton.icon(
                          onPressed: vm.isSubmitting
                              ? null
                              : () => _resolve(
                                    context,
                                    vm,
                                    keepRemote: false,
                                  ),
                          icon: const Icon(Icons.phone_android_outlined),
                          label: const Text('Conservar mis cambios'),
                        ),
                      ),
                    ),
                  ]
                : [
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: vm.isSubmitting
                            ? null
                            : () async {
                                final updated =
                                    await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        RabbitCreateRoute(rabbit: r),
                                  ),
                                );
                                if (updated == true && context.mounted) {
                                  Navigator.of(context).pop(true);
                                }
                              },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                          side: BorderSide(color: scheme.error),
                        ),
                        onPressed: vm.isSubmitting
                            ? null
                            : () => _confirmDelete(context, vm, r),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar'),
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }

  Future<void> _resolve(
    BuildContext context,
    RabbitViewModel vm, {
    required bool keepRemote,
  }) async {
    final updated = keepRemote
        ? await vm.resolveConflictKeepRemote(_rabbit.uuid)
        : await vm.resolveConflictKeepLocal(_rabbit.uuid);
    if (!context.mounted) return;
    if (updated != null) {
      setState(() => _rabbit = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            keepRemote
                ? 'Se conservó la versión del servidor.'
                : 'Se conservaron tus cambios.',
          ),
        ),
      );
      return;
    }
    final msg = switch (vm.submitState) {
      SubmitFailed(:final message) => message,
      _ => 'No se pudo resolver el conflicto',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    RabbitViewModel vm,
    Rabbit current,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '¿Eliminar conejo?',
          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
        ),
        content: Text(
          '¿Quitar a «${current.name}»? No se puede deshacer.',
          style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface,
                height: 1.4,
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final deleted = await vm.deleteRabbit(current.uuid);
    if (!context.mounted) return;
    if (deleted) {
      Navigator.of(context).pop(true);
      return;
    }
    final msg = switch (vm.submitState) {
      SubmitFailed(:final message) => message,
      _ => 'No se pudo eliminar',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _FichaRow extends StatelessWidget {
  const _FichaRow({
    required this.label,
    required this.value,
    required this.order,
  });

  final String label;
  final String value;
  final double order;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      sortKey: OrdinalSortKey(order),
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: textTheme.labelLarge?.copyWith(
                  color: scheme.onSurface.withOpacity(0.75),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
