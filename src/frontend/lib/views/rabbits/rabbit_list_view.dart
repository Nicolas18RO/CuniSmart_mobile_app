import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/cuni_theme.dart';
import '../../core/state/async_view_state.dart';
import '../../core/state/submit_state.dart';
import '../../models/rabbit.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/rabbit_viewmodel.dart';
import '../../viewmodels/voice_viewmodel.dart';
import '../../features/rabbits/presentation/widgets/floating_actions.dart';
import '../../features/rabbits/presentation/widgets/rabbit_card.dart';
import '../../features/rabbits/presentation/widgets/rabbits_header.dart';
import 'rabbit_create_route.dart';

class RabbitListView extends StatefulWidget {
  const RabbitListView({super.key});

  @override
  State<RabbitListView> createState() => _RabbitListViewState();
}

class _RabbitListViewState extends State<RabbitListView> {
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
    final voice = context.watch<VoiceViewModel>();
    return Scaffold(
      backgroundColor: CuniTheme.rabbitsBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                RabbitsHeader(
                  title: 'Conejos',
                  onProfile: () => context.read<AuthViewModel>().logout(),
                  onChat: () {},
                  onRefresh: vm.isListLoading ? null : () => vm.loadRabbits(),
                ),
                Expanded(child: _buildBody(context, vm)),
              ],
            ),
            FloatingActions(
              onMic: () async {
                await context.read<VoiceViewModel>().toggleMicrophone();
              },
              isListening: voice.isVoiceModeEnabled,
              isProcessing: voice.isProcessing,
              onAdd: vm.shouldBlockCreateFab
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
            ),
          ],
        ),
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: rabbits.length,
      itemBuilder: (context, i) {
        final r = rabbits[i];
        final vm = context.read<RabbitViewModel>();

        return RabbitCard(
          rabbit: r,
          onEdit: vm.isSubmitting
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
          onDelete: vm.isSubmitting ? null : () => _confirmDelete(context, vm, r),
        );
      },
    );
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
