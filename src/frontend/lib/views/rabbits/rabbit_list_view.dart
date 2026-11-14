import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/async_view_state.dart';
import '../../core/state/submit_state.dart';
import '../../core/theme/cuni_theme.dart';
import '../../features/auth/presentation/screens/security_settings_screen.dart';
import '../../features/r3/presentation/genealogy_views.dart';
import '../../features/r3/presentation/reproductive_views.dart';
import '../../models/rabbit.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/rabbit_viewmodel.dart';
import 'rabbit_create_route.dart';
import 'rabbit_detail_view.dart';
import 'rabbit_qr_scan_view.dart';
import 'widgets/rabbit_presentation.dart';
import '../../widgets/voice_mic_fab.dart';

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
      backgroundColor: CuniTheme.lightGrayBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          'Conejos',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Genealogía y reproducción',
            icon: const Icon(Icons.account_tree_outlined),
            onSelected: (value) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => value == 'reproduction'
                    ? const ReproductiveEventListView()
                    : const KinshipView(),
              ));
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'kinship',
                child: ListTile(
                  leading: Icon(Icons.calculate_outlined),
                  title: Text('Consultar parentesco'),
                ),
              ),
              PopupMenuItem(
                value: 'reproduction',
                child: ListTile(
                  leading: Icon(Icons.family_restroom_outlined),
                  title: Text('Gestión reproductiva'),
                ),
              ),
            ],
          ),
          IconButton(
            iconSize: 28,
            constraints:
                const BoxConstraints(minWidth: _iconTap, minHeight: _iconTap),
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthViewModel>().logout(),
            tooltip: 'Cerrar sesión',
          ),
          IconButton(
            iconSize: 28,
            constraints:
                const BoxConstraints(minWidth: _iconTap, minHeight: _iconTap),
            icon: const Icon(Icons.security),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AuthSecuritySettingsScreen(),
                ),
              );
            },
            tooltip: 'Seguridad',
          ),
          Semantics(
            button: true,
            label: 'Escanear código QR',
            child: IconButton(
              iconSize: 28,
              constraints: const BoxConstraints(
                minWidth: _iconTap,
                minHeight: _iconTap,
              ),
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Escanear código QR',
              onPressed: () => _scanQr(context),
            ),
          ),
          IconButton(
            iconSize: 28,
            constraints:
                const BoxConstraints(minWidth: _iconTap, minHeight: _iconTap),
            icon: const Icon(Icons.refresh),
            onPressed: vm.isListLoading ? null : () => vm.loadRabbits(),
            tooltip: 'Actualizar lista',
          ),
        ],
      ),
      body: _buildBody(context, vm),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Semantics(
            button: true,
            label: 'Crear nuevo conejo',
            child: FloatingActionButton.large(
              heroTag: 'rabbit_create_fab',
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
              tooltip: 'Crear nuevo conejo',
              elevation: 4,
              child: const Icon(Icons.add),
            ),
          ),
          const SizedBox(height: 16),
          const VoiceMicFab(heroTag: 'voice_mic_rabbits'),
        ],
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
      AsyncSuccess<List<Rabbit>>(:final data) =>
        _buildSuccessBody(context, vm, data),
      AsyncError<List<Rabbit>>(:final message, :final cachedData) =>
        _buildErrorBody(context, vm, message, cachedData),
    };
  }

  Widget _subtitle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        'Gestiona la información de tus conejos',
        style: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface.withOpacity(0.72),
          height: 1.35,
        ),
      ),
    );
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
        _subtitle(context),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _subtitle(context),
        Expanded(
          child: data.isEmpty
              ? _emptyPlaceholder(context)
              : _rabbitList(context, data),
        ),
      ],
    );
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                  textStyle: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
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
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(88, 48),
                    foregroundColor: scheme.onErrorContainer,
                  ),
                  onPressed: vm.isListLoading ? null : () => vm.loadRabbits(),
                  child:
                      const Text('Reintentar', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
        _subtitle(context),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemCount: rabbits.length,
      itemBuilder: (context, i) {
        final r = rabbits[i];
        final vm = context.read<RabbitViewModel>();
        return _RabbitCompactCard(
          rabbit: r,
          iconTap: _iconTap,
          onOpen: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => RabbitDetailView(rabbit: r),
              ),
            );
            if (changed == true && context.mounted) {
              await context.read<RabbitViewModel>().loadRabbits();
            }
          },
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
          onDelete:
              vm.isSubmitting ? null : () => _confirmDelete(context, vm, r),
        );
      },
    );
  }

  Future<void> _scanQr(BuildContext context) async {
    final rabbit = await Navigator.of(context).push<Rabbit>(
      MaterialPageRoute(builder: (_) => const RabbitQrScanView()),
    );
    if (rabbit == null || !context.mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RabbitDetailView(
          rabbit: rabbit,
          announceOnOpen: true,
        ),
      ),
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
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final deleted = await vm.deleteRabbit(rabbit.uuid);
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

class _RabbitCompactCard extends StatelessWidget {
  const _RabbitCompactCard({
    required this.rabbit,
    required this.iconTap,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Rabbit rabbit;
  final double iconTap;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final r = rabbit;
    final weight = rabbitWeightLabel(r);

    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: CuniTheme.borderGray, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            RabbitAvatar(name: r.name, radius: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: 'Abrir detalles de ${r.name}',
                          excludeSemantics: true,
                          child: InkWell(
                            onTap: onOpen,
                            borderRadius: BorderRadius.circular(8),
                            child: Text(
                              r.name,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                                height: 1.15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      RabbitStatusChip(
                        status: r.status,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: onOpen,
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.breed,
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurface.withOpacity(0.78),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            weight,
                            style: textTheme.bodyMedium?.copyWith(
                              color: CuniTheme.darkGray,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  button: true,
                  label: 'Editar conejo ${r.name}',
                  child: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    iconSize: 24,
                    tooltip: 'Editar conejo ${r.name}',
                    constraints: BoxConstraints(
                      minWidth: iconTap,
                      minHeight: iconTap,
                    ),
                    onPressed: onEdit,
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Eliminar conejo ${r.name}',
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    iconSize: 24,
                    tooltip: 'Eliminar conejo ${r.name}',
                    constraints: BoxConstraints(
                      minWidth: iconTap,
                      minHeight: iconTap,
                    ),
                    color: scheme.error,
                    onPressed: onDelete,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
