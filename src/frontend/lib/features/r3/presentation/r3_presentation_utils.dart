import 'package:flutter/material.dart';

import '../../../core/state/async_view_state.dart';
import '../../../core/state/submit_state.dart';
import '../../../models/rabbit.dart';
import '../../../viewmodels/rabbit_viewmodel.dart';
import '../domain/r3_models.dart';
import '../domain/r3_local_results.dart';

class R3CoverageSummary extends StatelessWidget {
  const R3CoverageSummary({super.key, required this.graph});
  final LocalGenealogy graph;

  @override
  Widget build(BuildContext context) {
    final coverage = switch (graph.coverage) {
      GenealogyCoverage.complete =>
        'Datos suficientes para las ramas consultadas.',
      GenealogyCoverage.incomplete => 'La genealogía local está incompleta.',
      GenealogyCoverage.unavailable =>
        'Falta una ficha necesaria para la consulta.',
      GenealogyCoverage.inconsistent =>
        'La genealogía local contiene inconsistencias.',
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: Text([
        'Copia local. $coverage',
        'Profundidad consultada: ${graph.depthExplored}.',
        if (graph.unknownParents.isNotEmpty)
          'Hay roles de progenitor desconocidos.',
        if (graph.unavailable.isNotEmpty)
          'Referencias sin ficha utilizable: ${graph.unavailable.length}.',
        if (graph.hasCycle) 'Ciclo genealógico detectado.',
        if (graph.depthLimited) 'Se alcanzó el límite de exploración.',
      ].join(' ')),
    );
  }
}

List<Rabbit> rabbitsFrom(RabbitViewModel vm) => switch (vm.listState) {
      AsyncSuccess<List<Rabbit>>(:final data) => data,
      AsyncLoading<List<Rabbit>>(:final cachedData) => cachedData ?? const [],
      AsyncError<List<Rabbit>>(:final cachedData) => cachedData ?? const [],
      _ => const [],
    };

String dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String relationshipLabel(String code) => switch (code) {
      'CURRENT' => 'Conejo actual',
      'FATHER' => 'Padre',
      'MOTHER' => 'Madre',
      'GRANDFATHER' => 'Abuelo',
      'GRANDMOTHER' => 'Abuela',
      'GREAT_GRANDFATHER' => 'Bisabuelo',
      'GREAT_GRANDMOTHER' => 'Bisabuela',
      'SON' => 'Hijo',
      'DAUGHTER' => 'Hija',
      'GRANDSON' => 'Nieto',
      'GRANDDAUGHTER' => 'Nieta',
      'GREAT_GRANDSON' => 'Bisnieto',
      'GREAT_GRANDDAUGHTER' => 'Bisnieta',
      'FATHER_SON' => 'Padre e hijo',
      'FATHER_DAUGHTER' => 'Padre e hija',
      'MOTHER_SON' => 'Madre e hijo',
      'MOTHER_DAUGHTER' => 'Madre e hija',
      'FULL_SIBLINGS' => 'Hermanos completos',
      'HALF_SIBLINGS' => 'Medios hermanos',
      'GRANDPARENT_GRANDCHILD' => 'Abuelo/a y nieto/a',
      'ANCESTOR_DESCENDANT' => 'Ascendiente y descendiente',
      'UNCLE_AUNT_NEPHEW_NIECE' => 'Tío/a y sobrino/a',
      'FIRST_COUSINS' => 'Primos hermanos',
      'UNRELATED' => 'Sin parentesco conocido',
      _ => 'Parentesco no determinado',
    };

String genealogyKnowledgeLabel(String code) => switch (code) {
      'FOUNDER' => 'fundador externo declarado independiente',
      'RECORDED' => 'genealogía registrada',
      _ => 'genealogía anterior desconocida',
    };

String kinshipResultTitle(KinshipEvaluation value) {
  if (!value.calculable && !value.hasKnownMinimum) {
    return 'No hay información suficiente para evaluar el cruce';
  }
  if (!value.isExact) {
    return 'Se detectó parentesco, pero falta información';
  }
  if (value.relationshipCoefficient == '0') {
    return 'Sin parentesco detectado';
  }
  if (value.riskLevel == 'ALTO') return 'Riesgo alto de consanguinidad';
  if (value.riskLevel == 'PREVENTIVO') {
    return 'Precaución: existe parentesco';
  }
  return 'Parentesco evaluado';
}

String kinshipExplanation(KinshipEvaluation value) {
  if (!value.calculable && !value.hasKnownMinimum) {
    return 'No se conocen los antecedentes genealógicos de uno o ambos '
        'animales y no se han declarado como fundadores independientes.';
  }
  if (!value.isExact) {
    return 'La relación mostrada es el mínimo demostrado. Como existen '
        'antepasados desconocidos, el porcentaje total podría ser mayor.';
  }
  if (value.relationshipCoefficient == '0' &&
      value.independenceAssumptionApplied) {
    return 'Los animales pertenecen a líneas fundadoras declaradas '
        'independientes. No se encontraron antepasados comunes en el '
        'pedigrí registrado.';
  }
  if (value.riskLevel == 'ALTO') {
    return 'Los animales presentan un parentesco cercano. Este cruce puede '
        'aumentar la probabilidad de características genéticas recesivas.';
  }
  if (value.riskLevel == 'PREVENTIVO') {
    return 'Se identificaron antepasados comunes y el cruce presenta un '
        'nivel preventivo de consanguinidad.';
  }
  return 'La evaluación se calculó con la genealogía registrada.';
}

String kinshipRecommendation(KinshipEvaluation value) {
  if (!value.calculable && !value.hasKnownMinimum) {
    return 'Registra su procedencia o completa su genealogía para obtener una '
        'evaluación confiable.';
  }
  if (value.riskLevel == 'ALTO') {
    return 'Recomendación: evita este cruce y evalúa otro reproductor.';
  }
  if (value.riskLevel == 'PREVENTIVO') {
    return 'Recomendación: compara este cruce con otro reproductor antes de '
        'decidir.';
  }
  if (value.independenceAssumptionApplied) {
    return 'Este resultado se basa en la información declarada y no garantiza '
        'ausencia de parentesco biológico fuera del registro.';
  }
  return 'La advertencia informa el riesgo y no bloquea el registro.';
}

String percentageLabel(String? value) {
  final decimal = double.tryParse(value ?? '');
  if (decimal == null) return 'No disponible';
  final percentage = decimal * 100;
  final digits = percentage == percentage.roundToDouble() ? 0 : 2;
  return '${percentage.toStringAsFixed(digits)} %';
}

String submitMessage(SubmitState state) => switch (state) {
      SubmitFailed(:final message) => message,
      _ => 'No se pudo completar la operación.',
    };

class R3Card extends StatelessWidget {
  const R3Card({super.key, required this.child, this.color});
  final Widget child;
  final Color? color;
  @override
  Widget build(BuildContext context) => Material(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );
}

class R3ErrorView extends StatelessWidget {
  const R3ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_outlined,
                size: 52, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar')),
          ]),
        ),
      );
}
