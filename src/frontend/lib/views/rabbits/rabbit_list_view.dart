import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/async_view_state.dart';
import '../../core/state/submit_state.dart';
import '../../models/rabbit.dart';
import '../../viewmodels/rabbit_viewmodel.dart';
import 'rabbit_create_route.dart';

class RabbitListView extends StatefulWidget {
  const RabbitListView({super.key});

  @override
  State<RabbitListView> createState() => _RabbitListViewState();
}

class _RabbitListViewState extends State<RabbitListView> {
  static const double _iconTap = 52;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RabbitViewModel>().loadRabbits();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RabbitViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Conejos',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            iconSize: 28,
            constraints: const BoxConstraints(minWidth: _iconTap, minHeight: _iconTap),
            icon: const Icon(Icons.refresh),
            onPressed: vm.isListLoading ? null : () => vm.loadRabbits(),
            tooltip: 'Actualizar lista',
          ),
        ],
      ),
      body: _buildBody(context, vm),
      floatingActionButton: FloatingActionButton.large(
        onPressed: vm.shouldBlockCreateFab
            ? null
            : () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const RabbitCreateRoute(),
                  ),
                );
                if (created == true && context.mounted) {
                  await context.read<RabbitViewModel>().loadRabbits();
                }
              },
        tooltip: 'Crear conejo',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(BuildContext context, RabbitViewModel vm) {
    return switch (vm.listState) {
      AsyncInitial<List<Rabbit>>() => const Center(
          child: CircularProgressIndicator(),
        ),
      AsyncLoading<List<Rabbit>>(:final cachedData) =>
        _buildLoadingBody(context, vm, cachedData),
      AsyncSuccess<List<Rabbit>>(:final data) => _buildSuccessBody(context, vm, data),
      AsyncError<List<Rabbit>>(:final message, :final cachedData) =>
        _buildErrorBody(context, vm, message, cachedData),
    };
  }

  Widget _buildLoadingBody(
    BuildContext context,
    RabbitViewModel vm,
    List<Rabbit>? cachedData,
  ) {
    if (cachedData == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(minHeight: 4),
        Expanded(
          child: cachedData.isEmpty
              ? _emptyPlaceholder(context)
              : _rabbitList(context, cachedData),
        ),
      ],
    );
  }

  Widget _buildSuccessBody(
    BuildContext context,
    RabbitViewModel vm,
    List<Rabbit> data,
  ) {
    if (data.isEmpty) return _emptyPlaceholder(context);
    return _rabbitList(context, data);
  }

  Widget _buildErrorBody(
    BuildContext context,
    RabbitViewModel vm,
    String message,
    List<Rabbit>? cachedData,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (cachedData == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 56,
                color: scheme.error,
              ),
              const SizedBox(height: 20),
              Text(
                'No se pudieron cargar los conejos',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(200, 52),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                onPressed: vm.isListLoading ? null : () => vm.loadRabbits(),
                icon: const Icon(Icons.refresh, size: 26),
                label: const Text('Volver a intentar'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: scheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 28,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: textTheme.bodyLarge?.copyWith(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(88, 48),
                    foregroundColor: scheme.onErrorContainer,
                  ),
                  onPressed: vm.isListLoading ? null : () => vm.loadRabbits(),
                  child: const Text('Reintentar', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: cachedData.isEmpty
              ? _emptyPlaceholder(context)
              : _rabbitList(context, cachedData),
        ),
      ],
    );
  }

  Widget _emptyPlaceholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Aún no hay conejos.\nToque el botón + para crear uno.',
          style: textTheme.titleMedium?.copyWith(
            color: scheme.onSurface,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _rabbitList(BuildContext context, List<Rabbit> rabbits) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemCount: rabbits.length,
      itemBuilder: (context, i) {
        final r = rabbits[i];
        final vm = context.read<RabbitViewModel>();

        return Material(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 6, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name,
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Raza',
                        style: textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface.withOpacity(0.75),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r.breed,
                        style: textTheme.titleMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Estado',
                        style: textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface.withOpacity(0.75),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _statusLabel(r.status),
                        style: textTheme.titleMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (r.weight != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Peso',
                          style: textTheme.labelLarge?.copyWith(
                            color: scheme.onSurface.withOpacity(0.75),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${r.weight!.toStringAsFixed(1)} kg',
                          style: textTheme.titleMedium?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      iconSize: 26,
                      tooltip: 'Editar',
                      constraints: const BoxConstraints(
                        minWidth: _iconTap,
                        minHeight: _iconTap,
                      ),
                      onPressed: vm.isSubmitting
                          ? null
                          : () async {
                              final updated = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => RabbitCreateRoute(rabbit: r),
                                ),
                              );
                              if (updated == true && context.mounted) {
                                await context.read<RabbitViewModel>().loadRabbits();
                              }
                            },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      iconSize: 26,
                      tooltip: 'Eliminar',
                      constraints: const BoxConstraints(
                        minWidth: _iconTap,
                        minHeight: _iconTap,
                      ),
                      color: scheme.error,
                      onPressed: vm.isSubmitting
                          ? null
                          : () => _confirmDelete(context, vm, r),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'active' => 'Activo',
      'sold' => 'Vendido',
      'deceased' => 'Fallecido',
      _ => status,
    };
  }

  Future<void> _confirmDelete(
    BuildContext context,
    RabbitViewModel vm,
    Rabbit rabbit,
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
          '¿Quitar a «${rabbit.name}»? No se puede deshacer.',
          style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface,
                height: 1.4,
              ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(120, 48),
              textStyle: const TextStyle(fontSize: 16),
            ),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(120, 48),
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final deleted = await vm.deleteRabbit(rabbit.id);
    if (!context.mounted) return;
    if (!deleted) {
      final msg = switch (vm.submitState) {
        SubmitFailed(:final message) => message,
        _ => 'No se pudo eliminar',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
