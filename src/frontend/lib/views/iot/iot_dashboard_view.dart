import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/async_view_state.dart';
import '../../models/rabbit.dart';
import '../../models/sensor_reading.dart';
import '../../viewmodels/rabbit_viewmodel.dart';
import '../../viewmodels/sensor_viewmodel.dart';

// --- Simple thresholds (UI-only heuristics; tune in one place) ---
const double _kLowWaterPercent = 30;
const double _kHighTempC = 28;
const double _kWeightDropAbsKg = 0.25;
const double _kWeightDropRatio = 0.88; // latest < prior * ratio → warning

class IoTDashboardView extends StatefulWidget {
  const IoTDashboardView({super.key});

  @override
  State<IoTDashboardView> createState() => _IoTDashboardViewState();
}

class _IoTDashboardViewState extends State<IoTDashboardView> {
  SensorViewModel? _sensorVm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vm = context.read<SensorViewModel>();
      _sensorVm = vm;
      vm.loadSensorReadings();
      vm.startPolling();
      context.read<RabbitViewModel>().loadRabbits();
    });
  }

  @override
  void dispose() {
    _sensorVm?.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sensorVm = context.watch<SensorViewModel>();
    final rabbitVm = context.watch<RabbitViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Farm sensors'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed:
                sensorVm.isLoading ? null : () => sensorVm.loadSensorReadings(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(context, sensorVm, rabbitVm),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SensorViewModel sensorVm,
    RabbitViewModel rabbitVm,
  ) {
    return switch (sensorVm.readingsState) {
      AsyncInitial<List<SensorReading>>() => const Center(
          child: CircularProgressIndicator(),
        ),
      AsyncLoading<List<SensorReading>>(:final cachedData) =>
        _buildLoadingBody(context, sensorVm, rabbitVm, cachedData),
      AsyncSuccess<List<SensorReading>>(:final data) =>
        _buildSuccessBody(context, sensorVm, rabbitVm, data),
      AsyncError<List<SensorReading>>(:final message, :final cachedData) =>
        _buildErrorBody(context, sensorVm, rabbitVm, message, cachedData),
    };
  }

  Widget _buildLoadingBody(
    BuildContext context,
    SensorViewModel sensorVm,
    RabbitViewModel rabbitVm,
    List<SensorReading>? cachedData,
  ) {
    if (cachedData == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(minHeight: 3),
        Expanded(
          child: _IoTDashboardScroll(
            sensorVm: sensorVm,
            rabbitVm: rabbitVm,
            readingsEmpty: cachedData.isEmpty,
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessBody(
    BuildContext context,
    SensorViewModel sensorVm,
    RabbitViewModel rabbitVm,
    List<SensorReading> data,
  ) {
    return _IoTDashboardScroll(
      sensorVm: sensorVm,
      rabbitVm: rabbitVm,
      readingsEmpty: data.isEmpty,
    );
  }

  Widget _buildErrorBody(
    BuildContext context,
    SensorViewModel sensorVm,
    RabbitViewModel rabbitVm,
    String message,
    List<SensorReading>? cachedData,
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
                'Could not load sensor readings',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed:
                    sensorVm.isLoading ? null : () => sensorVm.loadSensorReadings(),
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
                  onPressed: sensorVm.isLoading
                      ? null
                      : () => sensorVm.loadSensorReadings(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _IoTDashboardScroll(
            sensorVm: sensorVm,
            rabbitVm: rabbitVm,
            readingsEmpty: cachedData.isEmpty,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Main scroll: Farm (now) → Rabbits (latest weight) → Alerts (warnings)
// ---------------------------------------------------------------------------

class _IoTDashboardScroll extends StatelessWidget {
  const _IoTDashboardScroll({
    required this.sensorVm,
    required this.rabbitVm,
    required this.readingsEmpty,
  });

  final SensorViewModel sensorVm;
  final RabbitViewModel rabbitVm;
  final bool readingsEmpty;

  @override
  Widget build(BuildContext context) {
    final alerts = _computeAlerts(sensorVm, rabbitVm);
    final status = alerts.isEmpty ? _FarmStatus.normal : _FarmStatus.warning;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const _SectionTitle('Farm overview', 'Right now'),
        const SizedBox(height: 8),
        _FarmOverviewCard(
          temperatureC: sensorVm.latestRoomTemperature,
          waterPercent: sensorVm.latestTankWaterLevel,
          status: status,
          noData: readingsEmpty,
        ),
        const SizedBox(height: 24),
        const _SectionTitle('Rabbits', 'Latest weight only'),
        const SizedBox(height: 8),
        _RabbitsSummaryBlock(
          sensorVm: sensorVm,
          rabbitVm: rabbitVm,
          readingsEmpty: readingsEmpty,
          onRabbitTap: (rabbitId, displayName) => _openRabbitWeightDetail(
            context,
            sensorVm,
            rabbitId,
            displayName,
          ),
        ),
        const SizedBox(height: 24),
        const _SectionTitle('Alerts', 'Things to check'),
        const SizedBox(height: 8),
        _AlertsBlock(alerts: alerts, readingsEmpty: readingsEmpty),
      ],
    );
  }
}

void _openRabbitWeightDetail(
  BuildContext context,
  SensorViewModel sensorVm,
  int rabbitId,
  String displayName,
) {
  final history = sensorVm.weightEvents
      .where((r) => r.rabbitId == rabbitId && r.weight != null)
      .take(5)
      .toList();

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Recent weights (newest first)',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (history.isEmpty)
                const Text('No weight readings for this rabbit yet.')
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final w = history[i].weight!;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        child: Text('${i + 1}'),
                      ),
                      title: Text(
                        '${w.toStringAsFixed(2)} kg',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

enum _FarmStatus { normal, warning }

List<String> _computeAlerts(SensorViewModel vm, RabbitViewModel rabbitVm) {
  final out = <String>[];
  final water = vm.latestTankWaterLevel;
  final temp = vm.latestRoomTemperature;

  if (water != null && water < _kLowWaterPercent) {
    out.add('Water tank looks low. Check the tank soon.');
  }
  if (temp != null && temp > _kHighTempC) {
    out.add('Room is very warm. Check ventilation or shade.');
  }

  final byRabbit = <int, List<SensorReading>>{};
  for (final r in vm.weightEvents) {
    final id = r.rabbitId;
    if (id == null || r.weight == null) continue;
    byRabbit.putIfAbsent(id, () => []).add(r);
  }
  for (final entry in byRabbit.entries) {
    final list = entry.value;
    if (list.length < 2) continue;
    final latest = list[0].weight!;
    final prior = list[1].weight!;
    if (latest < prior - _kWeightDropAbsKg ||
        (prior > 0 && latest < prior * _kWeightDropRatio)) {
      out.add(
        'Weight went down for ${_rabbitLabel(entry.key, rabbitVm)}. Take a look.',
      );
    }
  }
  return out;
}

/// Latest weight per rabbit (newest event wins). Uses [SensorViewModel.weightEvents] order.
Map<int, double> _latestWeightByRabbit(SensorViewModel vm) {
  final m = <int, double>{};
  for (final r in vm.weightEvents) {
    final id = r.rabbitId;
    if (id == null || r.weight == null) continue;
    m.putIfAbsent(id, () => r.weight!);
  }
  return m;
}

String _rabbitLabel(int rabbitId, RabbitViewModel? rabbitVm) {
  if (rabbitVm == null) return 'Rabbit #$rabbitId';
  final state = rabbitVm.listState;
  if (state is AsyncSuccess<List<Rabbit>>) {
    for (final r in state.data) {
      if (r.id == rabbitId) return r.name;
    }
  }
  return 'Rabbit #$rabbitId';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: t.titleLarge),
        Text(
          subtitle,
          style: t.bodySmall?.copyWith(
            color: t.bodySmall?.color?.withOpacity(0.75),
          ),
        ),
      ],
    );
  }
}

class _FarmOverviewCard extends StatelessWidget {
  const _FarmOverviewCard({
    required this.temperatureC,
    required this.waterPercent,
    required this.status,
    required this.noData,
  });

  final double? temperatureC;
  final double? waterPercent;
  final _FarmStatus status;
  final bool noData;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final statusLabel = noData
        ? 'No sensor data yet'
        : switch (status) {
            _FarmStatus.normal => 'Status: All normal',
            _FarmStatus.warning => 'Status: Needs attention',
          };

    final statusColor = noData
        ? scheme.outline
        : switch (status) {
            _FarmStatus.normal => scheme.primary,
            _FarmStatus.warning => scheme.tertiary,
          };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.thermostat, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    temperatureC != null
                        ? 'Room: ${temperatureC!.toStringAsFixed(1)} °C'
                        : 'Room temperature: —',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.water_drop_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    waterPercent != null
                        ? 'Water tank: ${waterPercent!.toStringAsFixed(0)}% full'
                        : 'Water tank: —',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RabbitsSummaryBlock extends StatelessWidget {
  const _RabbitsSummaryBlock({
    required this.sensorVm,
    required this.rabbitVm,
    required this.readingsEmpty,
    required this.onRabbitTap,
  });

  final SensorViewModel sensorVm;
  final RabbitViewModel rabbitVm;
  final bool readingsEmpty;
  final void Function(int rabbitId, String displayName) onRabbitTap;

  @override
  Widget build(BuildContext context) {
    final weights = _latestWeightByRabbit(sensorVm);
    final rabbitState = rabbitVm.listState;

    if (rabbitState is AsyncSuccess<List<Rabbit>> && rabbitState.data.isNotEmpty) {
      return Column(
        children: [
          for (final rabbit in rabbitState.data)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  rabbit.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(
                  weights.containsKey(rabbit.id)
                      ? '${weights[rabbit.id]!.toStringAsFixed(2)} kg'
                      : 'No weight reading yet',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onRabbitTap(rabbit.id, rabbit.name),
              ),
            ),
        ],
      );
    }

    if (rabbitState is AsyncLoading<List<Rabbit>> ||
        rabbitState is AsyncInitial<List<Rabbit>>) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Error or empty rabbit list: fall back to rabbits seen in sensor data only.
    if (weights.isEmpty) {
      return Text(
        readingsEmpty
            ? 'Add rabbits on the Rabbits tab, or wait for the first weight reading.'
            : 'No weight readings yet. When a scale records a weight, rabbits appear here.',
      );
    }

    final ids = weights.keys.toList()..sort();
    return Column(
      children: [
        for (final id in ids)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(
                _rabbitLabel(id, rabbitVm),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text('${weights[id]!.toStringAsFixed(2)} kg'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onRabbitTap(id, _rabbitLabel(id, rabbitVm)),
            ),
          ),
      ],
    );
  }
}

class _AlertsBlock extends StatelessWidget {
  const _AlertsBlock({required this.alerts, required this.readingsEmpty});

  final List<String> alerts;
  final bool readingsEmpty;

  @override
  Widget build(BuildContext context) {
    if (readingsEmpty) {
      return const Text('No alerts until sensors send data.');
    }
    if (alerts.isEmpty) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.check_circle_outline, color: Theme.of(context).colorScheme.primary),
          title: const Text('No warnings right now.'),
        ),
      );
    }
    return Column(
      children: [
        for (final line in alerts)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                Icons.notifications_active_outlined,
                color: Theme.of(context).colorScheme.tertiary,
              ),
              title: Text(line),
            ),
          ),
      ],
    );
  }
}
