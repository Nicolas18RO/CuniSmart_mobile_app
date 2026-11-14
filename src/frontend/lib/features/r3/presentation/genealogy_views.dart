import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/state/async_view_state.dart';
import '../../../core/theme/cuni_theme.dart';
import '../../../models/rabbit.dart';
import '../../../viewmodels/rabbit_viewmodel.dart';
import '../../../views/rabbits/rabbit_detail_view.dart';
import '../domain/r3_models.dart';
import 'r3_presentation_utils.dart';
import 'r3_view_model.dart';

class GenealogyView extends StatefulWidget {
  const GenealogyView({super.key, required this.rabbit});
  final Rabbit rabbit;
  @override
  State<GenealogyView> createState() => _GenealogyViewState();
}

class _GenealogyViewState extends State<GenealogyView> {
  int? _generation;
  String? fatherUuid;
  String? motherUuid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vm = context.read<R3ViewModel>();
      _generation = vm.currentGeneration;
      vm.loadPedigree(widget.rabbit.uuid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<R3ViewModel>();
    final rabbits = rabbitsFrom(context.watch<RabbitViewModel>())
        .where((r) =>
            r.uuid != widget.rabbit.uuid &&
            r.status == 'active' &&
            r.deletedAt == null)
        .toList();
    return Scaffold(
      backgroundColor: CuniTheme.lightGrayBackground,
      appBar: AppBar(
          title: Text('Genealogía de ${widget.rabbit.name}'),
          backgroundColor: Colors.white),
      body: !vm.accepts(_generation) && _generation != null
          ? const Center(child: Text('La sesión cambió'))
          : switch (vm.pedigreeState) {
              AsyncInitial<Pedigree>() ||
              AsyncLoading<Pedigree>() =>
                const Center(child: CircularProgressIndicator()),
              AsyncError<Pedigree>(:final message) => R3ErrorView(
                  message: message,
                  onRetry: () => vm.loadPedigree(widget.rabbit.uuid)),
              AsyncSuccess<Pedigree>(:final data) =>
                _content(context, vm, data, rabbits),
            },
    );
  }

  Widget _content(BuildContext context, R3ViewModel vm, Pedigree data,
      List<Rabbit> rabbits) {
    final males = rabbits.where((r) => r.sex == 'male').toList();
    final females = rabbits.where((r) => r.sex == 'female').toList();
    return RefreshIndicator(
      onRefresh: () => vm.loadPedigree(widget.rabbit.uuid),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (data.local case final graph?) ...[
          Text(vm.sourceLabel),
          R3CoverageSummary(graph: graph),
          if (graph.deletedLinks.isNotEmpty)
            ExpansionTile(
                title: const Text('Historial de relaciones eliminadas'),
                children: [
                  for (final edge in graph.deletedLinks)
                    ListTile(
                        title: Text(
                            relationshipLabel(edge.link.role.storageValue)),
                        subtitle: Text(
                            '${edge.parent.rabbit?.name ?? edge.parent.uuid} · Eliminado localmente')),
                ]),
        ],
        R3Card(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Text('Progenitores',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _parentRow(context, vm, data, 'FATHER', 'Padre', data.father,
                  males, fatherUuid, (v) => setState(() => fatherUuid = v)),
              const Divider(height: 28),
              _parentRow(context, vm, data, 'MOTHER', 'Madre', data.mother,
                  females, motherUuid, (v) => setState(() => motherUuid = v)),
            ])),
        const SizedBox(height: 12),
        if (data.individualInbreeding case final individual?) ...[
          R3Card(
              color: individual.riskLevel == 'ALTO'
                  ? Theme.of(context).colorScheme.errorContainer
                  : null,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Consanguinidad de ${widget.rabbit.name}',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(individual.status == 'NO_CALCULABLE'
                        ? 'Consanguinidad individual no calculable con los datos disponibles.'
                        : individual.isExact
                            ? 'Coeficiente individual exacto: ${percentageLabel(individual.coefficient)}'
                            : 'Mínimo conocido: ${percentageLabel(individual.minimumKnownCoefficient)}'),
                    Text('Riesgo: ${individual.riskLevel}'),
                    if (individual.status == 'PARTIAL')
                      const Text(
                          'Estimación parcial: hay ramas genealógicas anteriores sin registrar.'),
                  ])),
          const SizedBox(height: 12),
        ],
        R3Card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Árbol por generaciones',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (data.ancestors.isEmpty)
            Text(data.local == null
                ? 'No hay ascendientes registrados.'
                : 'No hay ascendientes en la copia local.'),
          ...data.ancestors
              .map((node) => _relativeTile(context, node, rabbits)),
        ])),
        const SizedBox(height: 12),
        R3Card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Descendientes', style: Theme.of(context).textTheme.titleLarge),
          if (data.descendants.isEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(data.local == null
                    ? 'No hay descendientes registrados.'
                    : 'No hay descendientes en la copia local.')),
          ...data.descendants
              .map((node) => _relativeTile(context, node, rabbits)),
        ])),
        if (data.integrity != 'VALID')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: R3Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Text(
                    'La genealogía contiene relaciones inconsistentes. ${data.integrityIssues.join(', ')}')),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => KinshipView(initialRabbit: widget.rabbit))),
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('Consultar parentesco'),
        ),
      ]),
    );
  }

  Widget _relativeTile(
      BuildContext context, PedigreeAnimal node, List<Rabbit> rabbits) {
    Rabbit? target;
    for (final rabbit in rabbits) {
      if (rabbit.uuid == node.uuid) target = rabbit;
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
          child: Icon(
              node.generation < 0 ? Icons.arrow_downward : Icons.arrow_upward)),
      title: Text(node.name),
      subtitle: Text(
          '${relationshipLabel(node.relationship)} · ${genealogyKnowledgeLabel(node.genealogyKnowledge)}${node.deleted ? ' · histórico' : ''}'),
      trailing: target == null ? null : const Icon(Icons.chevron_right),
      onTap: target == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => RabbitDetailView(rabbit: target!)),
              ),
    );
  }

  Widget _parentRow(
      BuildContext context,
      R3ViewModel vm,
      Pedigree pedigree,
      String role,
      String label,
      PedigreeAnimal? current,
      List<Rabbit> candidates,
      String? selected,
      ValueChanged<String?> onChanged) {
    final version = pedigree.versionFor(role, childUuid: widget.rabbit.uuid);
    final localEdges = pedigree.local?.links.where((edge) =>
        edge.link.childUuid == widget.rabbit.uuid &&
        edge.link.role.storageValue == role);
    final edge =
        localEdges != null && localEdges.isNotEmpty ? localEdges.first : null;
    final selection =
        candidates.any((rabbit) => rabbit.uuid == selected) ? selected : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('$label actual: ${current?.name ?? 'Desconocido'}'),
      if (edge?.link.syncStatus.storageValue.startsWith('PENDING') == true)
        const Text('Cambio guardado localmente. Publicación pendiente.'),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: selection,
        decoration: InputDecoration(labelText: 'Seleccionar $label'),
        items: candidates
            .map((r) => DropdownMenuItem(value: r.uuid, child: Text(r.name)))
            .toList(),
        onChanged: vm.submitting ? null : onChanged,
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: FilledButton(
          onPressed: selection == null || vm.submitting
              ? null
              : () async {
                  final ok = await vm.setParent(
                      child: widget.rabbit.uuid,
                      role: role,
                      parent: selection,
                      expectedGeneration: _generation,
                      version: version);
                  if (ok && context.mounted) {
                    onChanged(null);
                  }
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(submitMessage(vm.submitState))));
                  }
                },
          child: Text(current == null ? 'Registrar' : 'Cambiar'),
        )),
        if (version != null) ...[
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: vm.submitting
                ? null
                : () => vm.clearParent(
                    child: widget.rabbit.uuid,
                    role: role,
                    version: version,
                    expectedGeneration: _generation),
            child: const Text('Quitar'),
          ),
        ],
      ]),
    ]);
  }
}

class KinshipView extends StatefulWidget {
  const KinshipView({super.key, this.initialRabbit});
  final Rabbit? initialRabbit;
  @override
  State<KinshipView> createState() => _KinshipViewState();
}

class _KinshipViewState extends State<KinshipView> {
  String? first;
  String? second;
  bool breeding = false;
  @override
  void initState() {
    super.initState();
    first = widget.initialRabbit?.uuid;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<R3ViewModel>();
    final rabbits = rabbitsFrom(context.watch<RabbitViewModel>());
    return Scaffold(
      backgroundColor: CuniTheme.lightGrayBackground,
      appBar: AppBar(
          title: const Text('Parentesco y consanguinidad'),
          backgroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        R3Card(
            child: Column(children: [
          _selector('Primer conejo', first, rabbits,
              (v) => setState(() => first = v)),
          const SizedBox(height: 12),
          _selector('Segundo conejo', second, rabbits,
              (v) => setState(() => second = v)),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Evaluar cruce reproductivo'),
              value: breeding,
              onChanged: (v) => setState(() => breeding = v)),
          SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: first == null || second == null || first == second
                    ? null
                    : () => vm.evaluate(first!, second!,
                        mode: breeding ? 'breeding' : 'relationship'),
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('Calcular'),
              )),
        ])),
        const SizedBox(height: 12),
        switch (vm.kinshipState) {
          AsyncInitial<KinshipEvaluation>() => const SizedBox.shrink(),
          AsyncLoading<KinshipEvaluation>() =>
            const Center(child: CircularProgressIndicator()),
          AsyncError<KinshipEvaluation>(:final message) => R3ErrorView(
              message: message,
              onRetry: () {
                if (first != null && second != null) {
                  vm.evaluate(first!, second!,
                      mode: breeding ? 'breeding' : 'relationship');
                }
              }),
          AsyncSuccess<KinshipEvaluation>(:final data) =>
            _result(context, data, rabbits),
        },
      ]),
    );
  }

  DropdownButtonFormField<String> _selector(String label, String? value,
          List<Rabbit> rabbits, ValueChanged<String?> changed) =>
      DropdownButtonFormField(
        value: value,
        decoration: InputDecoration(labelText: label),
        items: rabbits
            .map((r) => DropdownMenuItem(value: r.uuid, child: Text(r.name)))
            .toList(),
        onChanged: changed,
      );

  Widget _result(
      BuildContext context, KinshipEvaluation value, List<Rabbit> rabbits) {
    String rabbitName(String? uuid) {
      for (final rabbit in rabbits) {
        if (rabbit.uuid == uuid) return rabbit.name;
      }
      return 'Conejo';
    }

    if (!value.calculable && !value.hasKnownMinimum) {
      final missing = value.unknownBranches
          .map(rabbitName)
          .toSet()
          .where((name) => name != 'Conejo')
          .join(', ');
      return R3Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (value.local case final graph?) R3CoverageSummary(graph: graph),
            Text(kinshipResultTitle(value),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('${rabbitName(first)} × ${rabbitName(second)}'),
            Text(
                'Relación detectada: ${relationshipLabel(value.relationshipType)}'),
            Text(kinshipExplanation(value)),
            if (missing.isNotEmpty) Text('Información faltante: $missing.'),
            const Text('Un valor desconocido no equivale a cero.'),
            const SizedBox(height: 8),
            Text(kinshipRecommendation(value)),
          ]));
    }
    final color = value.riskLevel == 'ALTO'
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.primaryContainer;
    return R3Card(
        color: color,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (value.local case final graph?) R3CoverageSummary(graph: graph),
          Text(kinshipResultTitle(value),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('${rabbitName(first)} × ${rabbitName(second)}'),
          Text('Relación: ${relationshipLabel(value.relationshipType)}'),
          Text(value.isExact
              ? 'Coeficiente de relación exacto: ${percentageLabel(value.relationshipCoefficient)}'
              : 'Coeficiente de relación mínimo conocido: ${percentageLabel(value.relationshipCoefficient)}'),
          Text(value.isExact
              ? 'Consanguinidad esperada exacta: ${percentageLabel(value.expectedInbreeding)}'
              : 'Consanguinidad esperada mínima conocida: ${percentageLabel(value.minimumKnownInbreeding)}'),
          Text('Riesgo: ${value.riskLevel}'),
          if (value.commonAncestors.isNotEmpty)
            Text(
                'Ancestros comunes: ${value.commonAncestors.map((item) => item.name.isEmpty ? item.uuid : item.name).join(', ')}'),
          if (value.declaredFounders.isNotEmpty)
            Text(
                'Líneas fundadoras declaradas: ${value.declaredFounders.join(', ')}'),
          const SizedBox(height: 8),
          Text(kinshipExplanation(value)),
          const SizedBox(height: 8),
          Text(kinshipRecommendation(value)),
        ]));
  }
}
