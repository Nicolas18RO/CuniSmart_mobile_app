import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/async_view_state.dart';
import '../../models/rabbit.dart';
import '../../viewmodels/rabbit_viewmodel.dart';
import 'rabbit_create_view.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('CuniSmart — Rabbits'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: vm.isListLoading ? null : () => vm.loadRabbits(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(context, vm),
      floatingActionButton: FloatingActionButton(
        onPressed: vm.shouldBlockCreateFab
            ? null
            : () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const RabbitCreateView(),
                  ),
                );
                if (created == true && context.mounted) {
                  await context.read<RabbitViewModel>().loadRabbits();
                }
              },
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
        const LinearProgressIndicator(minHeight: 3),
        Expanded(
          child: cachedData.isEmpty
              ? _emptyPlaceholder()
              : _rabbitList(cachedData),
        ),
      ],
    );
  }

  Widget _buildSuccessBody(
    BuildContext context,
    RabbitViewModel vm,
    List<Rabbit> data,
  ) {
    if (data.isEmpty) return _emptyPlaceholder();
    return _rabbitList(data);
  }

  Widget _buildErrorBody(
    BuildContext context,
    RabbitViewModel vm,
    String message,
    List<Rabbit>? cachedData,
  ) {
    if (cachedData == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Could not load rabbits',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: vm.isListLoading ? null : () => vm.loadRabbits(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
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
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: vm.isListLoading ? null : () => vm.loadRabbits(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: cachedData.isEmpty
              ? _emptyPlaceholder()
              : _rabbitList(cachedData),
        ),
      ],
    );
  }

  Widget _emptyPlaceholder() {
    return const Center(
      child: Text('No rabbits yet. Tap + to add one.'),
    );
  }

  Widget _rabbitList(List<Rabbit> rabbits) {
    return ListView.builder(
      itemCount: rabbits.length,
      itemBuilder: (context, i) {
        final r = rabbits[i];
        final subtitle =
            '${r.breed} · ${r.sex} · ${r.status}${r.weight != null ? ' · ${r.weight} kg' : ''}';
        return ListTile(
          title: Text(r.name),
          subtitle: Text(subtitle),
        );
      },
    );
  }
}
