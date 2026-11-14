import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/state/async_view_state.dart';
import '../../../core/theme/cuni_theme.dart';
import '../../../models/rabbit.dart';
import '../../../viewmodels/rabbit_viewmodel.dart';
import '../domain/r3_models.dart';
import '../domain/r3_local_results.dart';
import 'r3_presentation_utils.dart';
import 'r3_view_model.dart';
import 'r3_sync_view.dart';
import '../../../services/r3_hydration_service.dart';

class ReproductiveEventListView extends StatefulWidget {
  const ReproductiveEventListView({super.key});
  @override
  State<ReproductiveEventListView> createState() =>
      _ReproductiveEventListViewState();
}

class _ReproductiveEventListViewState extends State<ReproductiveEventListView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<R3ViewModel>().loadEvents();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<R3ViewModel>();
    final rabbits = rabbitsFrom(context.watch<RabbitViewModel>());
    return Scaffold(
      backgroundColor: CuniTheme.lightGrayBackground,
      appBar: AppBar(
          title: const Text('Gestión reproductiva'),
          backgroundColor: Colors.white,
          actions: [
            if (context.read<R3HydrationService?>() != null)
              IconButton(
                tooltip: 'Sincronización y conflictos R3',
                icon: const Icon(Icons.sync),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const R3SyncView(),
                  ));
                  if (context.mounted) await vm.loadEvents();
                },
              ),
            if (vm.localData)
              IconButton(
                tooltip: 'Filtrar historial reproductivo',
                icon: const Icon(Icons.filter_list),
                onPressed: () => _filter(vm, rabbits),
              ),
            IconButton(
              tooltip: 'Calendario reproductivo',
              icon: const Icon(Icons.calendar_month_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ReproductiveCalendarView())),
            ),
          ]),
      body: switch (vm.eventsState) {
        AsyncInitial<List<ReproductiveEvent>>() ||
        AsyncLoading<List<ReproductiveEvent>>() =>
          const Center(child: CircularProgressIndicator()),
        AsyncError<List<ReproductiveEvent>>(:final message) =>
          R3ErrorView(message: message, onRetry: vm.loadEvents),
        AsyncSuccess<List<ReproductiveEvent>>(:final data) => data.isEmpty
            ? Center(
                child: Text(vm.localData
                    ? 'No hay eventos en la copia local.'
                    : 'Aún no hay eventos reproductivos.'))
            : RefreshIndicator(
                onRefresh: vm.loadEvents,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: data.length,
                  itemBuilder: (_, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _EventCard(
                        event: data[index],
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ReproductiveEventDetailView(
                                  event: data[index],
                                  rabbits: rabbits,
                                  sessionGeneration: vm.currentGeneration),
                            ))),
                  ),
                )),
      },
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ReproductiveEventFormView(rabbits: rabbits))),
        icon: const Icon(Icons.add),
        label: const Text('Registrar monta'),
      ),
    );
  }

  Future<void> _filter(R3ViewModel vm, List<Rabbit> rabbits) async {
    final generation = vm.currentGeneration;
    final result = await showDialog<_EventFilter>(
      context: context,
      builder: (_) => _EventFilterDialog(vm: vm, rabbits: rabbits),
    );
    if (!mounted || result == null || !vm.accepts(generation)) return;
    await vm.filterEvents(
        participant: result.participant,
        role: result.role,
        from: result.from,
        to: result.to,
        includeDeleted: result.deleted);
  }
}

typedef _EventFilter = ({
  String? participant,
  ReproductiveRole? role,
  String? from,
  String? to,
  bool deleted,
});

class _EventFilterDialog extends StatefulWidget {
  const _EventFilterDialog({required this.vm, required this.rabbits});
  final R3ViewModel vm;
  final List<Rabbit> rabbits;

  @override
  State<_EventFilterDialog> createState() => _EventFilterDialogState();
}

class _EventFilterDialogState extends State<_EventFilterDialog> {
  late String? participant = widget.vm.participant;
  late ReproductiveRole? role = widget.vm.participantRole;
  late String? from = widget.vm.fromDate;
  late String? to = widget.vm.toDate;
  late bool deleted = widget.vm.includeDeletedEvents;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Historial reproductivo local'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: widget.rabbits.any((rabbit) => rabbit.uuid == participant)
                ? participant
                : null,
            decoration: const InputDecoration(labelText: 'Participante'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Todos')),
              for (final rabbit in widget.rabbits)
                DropdownMenuItem(value: rabbit.uuid, child: Text(rabbit.name)),
            ],
            onChanged: (value) => setState(() {
              participant = value == '' ? null : value;
              if (participant == null) role = null;
            }),
          ),
          DropdownButtonFormField<ReproductiveRole>(
            value: role,
            decoration:
                const InputDecoration(labelText: 'Rol del participante'),
            items: const [
              DropdownMenuItem(child: Text('Cualquier rol')),
              DropdownMenuItem(
                  value: ReproductiveRole.male, child: Text('Macho')),
              DropdownMenuItem(
                  value: ReproductiveRole.female, child: Text('Hembra')),
            ],
            onChanged: participant == null
                ? null
                : (value) => setState(() => role = value),
          ),
          ListTile(
              title: Text('Desde: ${from ?? 'sin límite'}'),
              onTap: () => _date(true)),
          ListTile(
              title: Text('Hasta: ${to ?? 'sin límite'}'),
              onTap: () => _date(false)),
          CheckboxListTile(
              title: const Text('Incluir eventos eliminados'),
              value: deleted,
              onChanged: (value) => setState(() => deleted = value ?? false)),
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, (
                    participant: null,
                    role: null,
                    from: null,
                    to: null,
                    deleted: false,
                  )),
              child: const Text('Limpiar')),
          FilledButton(
              onPressed: from != null && to != null && from!.compareTo(to!) > 0
                  ? null
                  : () => Navigator.pop(context, (
                        participant: participant,
                        role: role,
                        from: from,
                        to: to,
                        deleted: deleted,
                      )),
              child: const Text('Aplicar')),
        ],
      );

  Future<void> _date(bool start) async {
    final value = await showDatePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDate: DateTime.now());
    if (!mounted || value == null) return;
    setState(() {
      if (start) {
        from = dateOnly(value);
      } else {
        to = dateOnly(value);
      }
    });
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, this.onTap});
  final ReproductiveEvent event;
  final VoidCallback? onTap;
  String get stateLabel => switch (event.calendarState) {
        'DUE_TODAY' => 'Parto previsto hoy',
        'OVERDUE' => 'Fecha prevista vencida',
        _ => 'Próximo',
      };
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: R3Card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('${event.maleName} × ${event.femaleName}',
                    style: Theme.of(context).textTheme.titleLarge)),
            const Icon(Icons.chevron_right)
          ]),
          const SizedBox(height: 8),
          if (event.local case final local?)
            Semantics(
              liveRegion: true,
              child: Text(local.deletedAt != null
                  ? 'Copia local. Evento eliminado.'
                  : 'Copia local. Cambios pendientes de publicación.'),
            ),
          Text('Monta: ${event.matingDate}'),
          Text('Parto probable: ${event.estimatedBirthDate}'),
          const SizedBox(height: 8),
          Chip(label: Text('$stateLabel · ${event.daysRemaining} días')),
        ])),
      );
}

class ReproductiveEventFormView extends StatefulWidget {
  const ReproductiveEventFormView(
      {super.key, required this.rabbits, this.event});
  final List<Rabbit> rabbits;
  final ReproductiveEvent? event;
  @override
  State<ReproductiveEventFormView> createState() =>
      _ReproductiveEventFormViewState();
}

class _ReproductiveEventFormViewState extends State<ReproductiveEventFormView> {
  int? _generation;
  String? male;
  String? female;
  late String date;
  late TextEditingController notes;
  @override
  void initState() {
    super.initState();
    _generation = context.read<R3ViewModel>().currentGeneration;
    male = widget.event?.maleUuid;
    female = widget.event?.femaleUuid;
    date = widget.event?.matingDate ?? dateOnly(DateTime.now());
    notes = TextEditingController(text: widget.event?.notes ?? '');
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<R3ViewModel>();
    if (!vm.accepts(_generation)) {
      return const Scaffold(body: Center(child: Text('La sesión cambió')));
    }
    final males = widget.rabbits
        .where((r) =>
            r.sex == 'male' && r.status == 'active' && r.deletedAt == null)
        .toList();
    final females = widget.rabbits
        .where((r) =>
            r.sex == 'female' && r.status == 'active' && r.deletedAt == null)
        .toList();
    final editing = widget.event != null;
    return Scaffold(
      backgroundColor: CuniTheme.lightGrayBackground,
      appBar: AppBar(
          title: Text(editing ? 'Editar evento' : 'Registrar monta'),
          backgroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        R3Card(
            child: Column(children: [
          if (!editing)
            DropdownButtonFormField<String>(
              value: males.any((r) => r.uuid == male) ? male : null,
              decoration: const InputDecoration(labelText: 'Macho'),
              items: males
                  .map((r) =>
                      DropdownMenuItem(value: r.uuid, child: Text(r.name)))
                  .toList(),
              onChanged: editing ? null : (v) => setState(() => male = v),
            ),
          const SizedBox(height: 12),
          if (!editing)
            DropdownButtonFormField<String>(
              value: females.any((r) => r.uuid == female) ? female : null,
              decoration: const InputDecoration(labelText: 'Hembra'),
              items: females
                  .map((r) =>
                      DropdownMenuItem(value: r.uuid, child: Text(r.name)))
                  .toList(),
              onChanged: editing ? null : (v) => setState(() => female = v),
            ),
          const SizedBox(height: 12),
          if (editing) Text(' × '),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fecha de monta'),
            subtitle: Text(date),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: _pickDate,
          ),
          const SizedBox(height: 12),
          TextField(
              controller: notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notas opcionales')),
          const SizedBox(height: 16),
          SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: !vm.accepts(_generation) ||
                        vm.submitting ||
                        male == null ||
                        female == null ||
                        male == female
                    ? null
                    : () => _save(vm),
                child: Text(editing ? 'Guardar cambios' : 'Registrar evento'),
              )),
        ])),
      ]),
    );
  }

  Future<void> _pickDate() async {
    final current = DateTime.parse(date);
    final value = await showDatePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDate: current);
    if (mounted && value != null) setState(() => date = dateOnly(value));
  }

  Future<void> _save(R3ViewModel vm) async {
    final ok = await vm.saveEvent(
        event: widget.event,
        male: male!,
        female: female!,
        date: date,
        notes: notes.text.trim(),
        expectedGeneration: _generation);
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(submitMessage(vm.submitState))));
    }
  }
}

class ReproductiveEventDetailView extends StatelessWidget {
  const ReproductiveEventDetailView(
      {super.key,
      required this.event,
      required this.rabbits,
      this.sessionGeneration});
  final ReproductiveEvent event;
  final List<Rabbit> rabbits;
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<R3ViewModel>();
    if (sessionGeneration != null && !vm.accepts(sessionGeneration)) {
      return const Scaffold(body: Center(child: Text('La sesión cambió')));
    }
    return Scaffold(
      backgroundColor: CuniTheme.lightGrayBackground,
      appBar: AppBar(
          title: const Text('Detalle reproductivo'),
          backgroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        _EventCard(event: event),
        const SizedBox(height: 12),
        R3Card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Evaluación genealógica',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (event.kinship.local case final graph?)
            R3CoverageSummary(graph: graph),
          Text(kinshipResultTitle(event.kinship),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(event.kinship.calculable
              ? 'Riesgo: ${event.kinship.riskLevel} · Consanguinidad esperada exacta: ${percentageLabel(event.kinship.expectedInbreeding)}'
              : event.kinship.hasKnownMinimum
                  ? 'Riesgo: ${event.kinship.riskLevel} · Consanguinidad mínima conocida: ${percentageLabel(event.kinship.minimumKnownInbreeding)} · estimación parcial'
                  : 'No existe un porcentaje confiable; un valor desconocido no equivale a cero.'),
          const SizedBox(height: 8),
          Text(kinshipExplanation(event.kinship)),
          Text(kinshipRecommendation(event.kinship)),
        ])),
        const SizedBox(height: 12),
        if (event.local?.deletedAt == null)
          FilledButton.icon(
            onPressed: () async {
              final updated = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                    builder: (_) => ReproductiveEventFormView(
                          rabbits: rabbits,
                          event: event,
                        )),
              );
              if (updated == true && context.mounted)
                Navigator.of(context).pop(true);
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar fecha o notas'),
          ),
        const SizedBox(height: 8),
        if (event.local?.deletedAt == null)
          OutlinedButton.icon(
            onPressed: () => _delete(context),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar evento'),
          ),
      ]),
    );
  }

  final int? sessionGeneration;

  Future<void> _delete(BuildContext context) async {
    final generation =
        sessionGeneration ?? context.read<R3ViewModel>().currentGeneration;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('¿Eliminar evento?'),
              content: const Text(
                  'El evento dejará de aparecer en la gestión y el calendario.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Eliminar'))
              ],
            ));
    if (confirmed != true || !context.mounted) {
      return;
    }
    final vm = context.read<R3ViewModel>();
    final ok = await vm.deleteEvent(event, expectedGeneration: generation);
    if (!context.mounted) {
      return;
    }
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(submitMessage(vm.submitState))));
    }
  }
}

class ReproductiveCalendarView extends StatefulWidget {
  const ReproductiveCalendarView({super.key});
  @override
  State<ReproductiveCalendarView> createState() =>
      _ReproductiveCalendarViewState();
}

class _ReproductiveCalendarViewState extends State<ReproductiveCalendarView> {
  late DateTime month;
  @override
  void initState() {
    super.initState();
    month = DateTime(DateTime.now().year, DateTime.now().month);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  void _load() {
    final end = DateTime(month.year, month.month + 1, 0);
    context.read<R3ViewModel>().loadCalendar(dateOnly(month), dateOnly(end));
  }

  void _move(int delta) {
    setState(() => month = DateTime(month.year, month.month + delta));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<R3ViewModel>();
    final state = vm.calendarState;
    return Scaffold(
      backgroundColor: CuniTheme.lightGrayBackground,
      appBar: AppBar(
          title: const Text('Calendario reproductivo'),
          backgroundColor: Colors.white),
      body: Column(children: [
        if (vm.localData) Text(vm.sourceLabel),
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                      tooltip: 'Mes anterior',
                      onPressed: () => _move(-1),
                      icon: const Icon(Icons.chevron_left)),
                  Text(
                      '${month.year}-${month.month.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                      tooltip: 'Mes siguiente',
                      onPressed: () => _move(1),
                      icon: const Icon(Icons.chevron_right)),
                ])),
        Expanded(
            child: switch (state) {
          AsyncInitial<List<ReproductiveEvent>>() ||
          AsyncLoading<List<ReproductiveEvent>>() =>
            const Center(child: CircularProgressIndicator()),
          AsyncError<List<ReproductiveEvent>>(:final message) =>
            R3ErrorView(message: message, onRetry: _load),
          AsyncSuccess<List<ReproductiveEvent>>(:final data) => data.isEmpty
              ? Center(
                  child: Text(vm.localData
                      ? 'No hay partos previstos en la copia local para este mes.'
                      : 'No hay partos previstos en este mes.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: data.length,
                  itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _EventCard(event: data[i]))),
        }),
      ]),
    );
  }
}
