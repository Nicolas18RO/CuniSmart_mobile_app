import '../../features/r3/application/r3_use_cases.dart';
import '../../features/r3/domain/r3_models.dart';
import '../../models/rabbit.dart';

/// Adaptador conversacional R3. Delega cálculos y solo transforma resultados a voz.
class R3VoiceFacade {
  R3VoiceFacade(this._useCases, {this.sessionGeneration, this.sessionUnlocked});
  final R3UseCases _useCases;
  final int Function()? sessionGeneration;
  final bool Function()? sessionUnlocked;

  Future<String?> answer(String raw, List<Rabbit> rabbits) async {
    final generation = sessionGeneration?.call();
    if (sessionUnlocked?.call() == false) return null;
    try {
      final result = await _answer(raw, rabbits);
      if (generation != sessionGeneration?.call() ||
          sessionUnlocked?.call() == false) {
        return null;
      }
      if (result != null && sessionGeneration != null) {
        return 'Según la copia local disponible. $result';
      }
      return result;
    } catch (_) {
      if (generation != sessionGeneration?.call() ||
          sessionUnlocked?.call() == false) {
        return null;
      }
      return 'No pude consultar los datos locales en este momento.';
    }
  }

  Future<String?> _answer(String raw, List<Rabbit> rabbits) async {
    final text = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[¿?¡!.,]'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    final parents = RegExp(
      r'(?:quienes son|quiénes son|muéstrame|muestrame) (?:los padres|la familia) de (.+)',
    ).firstMatch(text);
    final father = RegExp(r'(?:quién es|quien es) el (?:papá|padre) de (.+)')
        .firstMatch(text);
    final mother = RegExp(r'(?:quién es|quien es) la (?:mamá|madre) de (.+)')
        .firstMatch(text);
    final children =
        RegExp(r'(?:cuantos|cuántos) hijos tiene (.+)').firstMatch(text);
    final childrenList =
        RegExp(r'(?:quienes son|quiénes son) los hijos de (.+)')
            .firstMatch(text);
    final descendants =
        RegExp(r'(?:quienes son|quiénes son) los descendientes de (.+)')
            .firstMatch(text);
    final hasDescendants =
        RegExp(r'^(.+?) tiene (?:descendientes|hijos)$').firstMatch(text);
    final kinship = RegExp(
      r'(.+?) se puede cruzar con (.+)|(?:qué )?parentesco (?:tienen|tiene) (.+?) (?:y|con) (.+)|'
      r'(?:qué )?riesgo tiene (?:el cruce de|cruzar a|el cruce entre) (.+?) (?:con|y) (.+)|'
      r'evalúa el cruce entre (.+?) y (.+)|(?:son familiares|son familia) (.+?) y (.+)|'
      r'(.+?) y (.+?) son familiares|(?:es recomendable|puedo) cruzar (?:a )?(.+?) con (.+)|'
      r'(?:calcula|calcular) la consanguinidad entre (.+?) y (.+)',
    ).firstMatch(text);
    final family = RegExp(
            r'(?:son familiares|son familia) (.+?) y (.+)|(.+?) y (.+?) son familiares')
        .firstMatch(text);
    final relationship =
        RegExp(r'(?:qué )?parentesco (?:tienen|tiene) (.+?) (?:y|con) (.+)')
            .firstMatch(text);
    final history =
        RegExp(r'^historial reproductivo de (.+)$').firstMatch(text);
    if (history != null && sessionGeneration != null) {
      final name = history.group(1)!.trim();
      final rabbit = _resolve(name, rabbits);
      if (rabbit == null) return _nameError(name, rabbits);
      final events = await _useCases.loadEvents(participant: rabbit.uuid);
      if (events.isEmpty)
        return 'No hay montas disponibles para ${rabbit.name}.';
      return '${rabbit.name} tiene ${events.length} eventos reproductivos disponibles. '
          'La última monta registrada fue el ${_formatDate(events.last.matingDate)}.';
    }
    try {
      if (parents != null) return _parents(parents.group(1)!.trim(), rabbits);
      if (father != null)
        return _singleParent(father.group(1)!.trim(), rabbits, father: true);
      if (mother != null)
        return _singleParent(mother.group(1)!.trim(), rabbits, father: false);
      if (children != null)
        return _children(children.group(1)!.trim(), rabbits);
      if (childrenList != null)
        return _childrenList(childrenList.group(1)!.trim(), rabbits);
      if (descendants != null)
        return _descendants(descendants.group(1)!.trim(), rabbits);
      if (hasDescendants != null) {
        return _hasDescendants(hasDescendants.group(1)!.trim(), rabbits);
      }
      if (family != null) {
        final values = [
          family.group(1),
          family.group(2),
          family.group(3),
          family.group(4)
        ].whereType<String>().toList();
        return _family(values[0], values[1], rabbits);
      }
      if (relationship != null) {
        return _relationship(relationship.group(1)!.trim(),
            relationship.group(2)!.trim(), rabbits);
      }
      if (kinship != null) {
        final values = [for (var i = 1; i <= 10; i++) kinship.group(i)]
            .whereType<String>()
            .toList();
        final first = values[0];
        final second = values[1];
        return _kinship(first.trim(), second.trim(), rabbits);
      }
      if (text.contains('nacen los próximos') ||
          text.contains('cuál es el próximo evento') ||
          text.contains('cual es el proximo evento') ||
          text.contains('próximo parto') ||
          text.contains('proximo parto') ||
          text.contains('qué evento de cría') ||
          text.contains('que evento de cria') ||
          text.contains('próximas a parir') ||
          text.contains('eventos de cría') ||
          text.contains('eventos reproductivos')) {
        return _eventsAnswer(text);
      }
    } catch (_) {
      return 'No pude consultar esa información ahora. Revisa la conexión e inténtalo de nuevo.';
    }
    return null;
  }

  Future<String> _parents(String name, List<Rabbit> rabbits) async {
    final rabbit = _resolve(name, rabbits);
    if (rabbit == null) return _nameError(name, rabbits);
    final p = await _useCases.loadPedigree(rabbit.uuid);
    return 'Los padres de ${rabbit.name} son ${p.father?.name ?? 'padre desconocido'} y ${p.mother?.name ?? 'madre desconocida'}.';
  }

  Future<String> _children(String name, List<Rabbit> rabbits) async {
    final rabbit = _resolve(name, rabbits);
    if (rabbit == null) return _nameError(name, rabbits);
    final p = await _useCases.loadPedigree(rabbit.uuid);
    final children = p.descendants.where((a) => a.generation == -1).toList();
    if (children.isEmpty)
      return 'No hay hijos registrados para ${rabbit.name}.';
    return _formatNodes(rabbit.name, children, 'hijo');
  }

  Future<String> _descendants(String name, List<Rabbit> rabbits) async {
    final rabbit = _resolve(name, rabbits);
    if (rabbit == null) return _nameError(name, rabbits);
    final p = await _useCases.loadPedigree(rabbit.uuid);
    final descendants = p.descendants.where((a) => a.generation < 0).toList();
    if (descendants.isEmpty)
      return 'No hay descendientes registrados para ${rabbit.name}.';
    return _formatNodes(rabbit.name, descendants, 'descendiente');
  }

  Future<String> _singleParent(String name, List<Rabbit> rabbits,
      {required bool father}) async {
    final rabbit = _resolve(name, rabbits);
    if (rabbit == null) return _nameError(name, rabbits);
    final p = await _useCases.loadPedigree(rabbit.uuid);
    final parent = father ? p.father?.name : p.mother?.name;
    if (parent == null) {
      return 'No hay ${father ? 'padre' : 'madre'} registrado para ${rabbit.name}.';
    }
    return 'El ${father ? 'padre' : 'la madre'} de ${rabbit.name} es $parent.';
  }

  Future<String> _kinship(
      String first, String second, List<Rabbit> rabbits) async {
    final a = _resolve(first, rabbits);
    final b = _resolve(second, rabbits);
    if (a == null) return _nameError(first, rabbits);
    if (b == null) return _nameError(second, rabbits);
    if (a.uuid == b.uuid)
      return 'Necesito dos conejos diferentes para evaluar el cruce.';
    final result = await _useCases.evaluate(a.uuid, b.uuid);
    if (result.status == 'NO_CALCULABLE')
      return 'No puedo calcular el riesgo entre ${a.name} y ${b.name}: falta información genealógica.';
    final risk = switch (result.riskLevel) {
      'PREVENTIVE' || 'PREVENTIVO' => 'preventivo',
      'HIGH' || 'ALTO' => 'alto',
      'NO_CALCULABLE' => 'no calculable',
      _ => 'sin advertencia'
    };
    final certainty = result.status == 'PARTIAL' || !result.isExact
        ? 'El resultado es parcial por datos incompletos.'
        : 'El resultado es exacto.';
    final relationship = _percent(result.relationshipCoefficient);
    final inbreeding = _percent(
      result.status == 'PARTIAL'
          ? result.minimumKnownInbreeding
          : result.expectedInbreeding,
    );
    return 'El cruce entre ${a.name} y ${b.name} tiene riesgo $risk. '
        'Parentesco: $relationship. Consanguinidad esperada de la descendencia: '
        '$inbreeding. $certainty';
  }

  Future<String> _relationship(
      String first, String second, List<Rabbit> rabbits) async {
    final result = await _evaluateNames(first, second, rabbits);
    if (result == null) return 'No pude identificar ambos conejos.';
    final (a, b, evaluation) = result;
    if (evaluation.status == 'NO_CALCULABLE')
      return 'No puedo determinar el parentesco entre ${a.name} y ${b.name}: faltan registros.';
    final relation = _relationshipLabel(evaluation.relationshipType);
    if (relation == 'sin parentesco conocido') {
      return '${a.name} y ${b.name} no tienen parentesco registrado en su genealogía.';
    }
    final verb = relation == 'una relación de padre e hijo'
        ? 'tienen'
        : relation == 'sin parentesco conocido'
            ? 'no tienen'
            : 'son';
    return '${a.name} y ${b.name} $verb $relation. ${evaluation.status == 'PARTIAL' ? 'La información es parcial.' : ''}'
        .trim();
  }

  Future<String> _family(
      String first, String second, List<Rabbit> rabbits) async {
    final result = await _evaluateNames(first, second, rabbits);
    if (result == null) return 'No pude identificar ambos conejos.';
    final (a, b, evaluation) = result;
    if (evaluation.status == 'NO_CALCULABLE')
      return 'No puedo confirmar si ${a.name} y ${b.name} son familiares porque faltan registros.';
    return evaluation.commonAncestors.isEmpty
        ? 'No encontré un ancestro común registrado entre ${a.name} y ${b.name}.'
        : 'Sí. ${a.name} y ${b.name} comparten un ancestro registrado.';
  }

  Future<(Rabbit, Rabbit, KinshipEvaluation)?> _evaluateNames(
      String first, String second, List<Rabbit> rabbits) async {
    final a = _resolve(first, rabbits);
    final b = _resolve(second, rabbits);
    if (a == null || b == null || a.uuid == b.uuid) return null;
    return (a, b, await _useCases.evaluate(a.uuid, b.uuid));
  }

  Future<String> _upcomingEvents() async {
    final events = await _useCases.loadEvents();
    final pending = events
        .where((e) =>
            e.calendarState == 'UPCOMING' || e.calendarState == 'DUE_TODAY')
        .toList()
      ..sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
    if (pending.isEmpty)
      return 'No tienes eventos reproductivos próximos registrados.';
    final e = pending.first;
    final when = e.daysRemaining == 0 ? 'hoy' : 'en ${e.daysRemaining} días';
    return 'El próximo nacimiento estimado es de ${e.femaleName}, $when, el ${_formatDate(e.estimatedBirthDate)}.';
  }

  Future<String> _eventsAnswer(String text) async {
    if (text.contains('esta semana') || text.contains('esta semana')) {
      return 'El calendario actual no permite filtrar eventos por semana desde voz.';
    }
    if (text.contains('próximas a parir') ||
        text.contains('proximas a parir') ||
        text.contains('van a parir')) {
      final events = await _useCases.loadEvents();
      final females = <String>{};
      for (final event in events) {
        if (event.calendarState == 'UPCOMING' ||
            event.calendarState == 'DUE_TODAY') {
          females.add(
              '${event.femaleName}, ${_formatDate(event.estimatedBirthDate)}');
        }
      }
      if (females.isEmpty)
        return 'No encontré conejas próximas a parir en los registros.';
      return 'Hay ${females.length} conejas próximas a parir: ${females.join('; ')}.';
    }
    if (text.contains('pendiente')) {
      final events = await _useCases.loadEvents();
      final pending = events
          .where((e) =>
              e.calendarState == 'UPCOMING' || e.calendarState == 'DUE_TODAY')
          .toList();
      if (pending.isEmpty) return 'No tienes eventos reproductivos pendientes.';
      return 'Tienes ${pending.length} eventos reproductivos pendientes.';
    }
    if (text.contains('registrados') || text.contains('tenemos')) {
      final events = await _useCases.loadEvents();
      if (events.isEmpty) return 'No tienes eventos reproductivos registrados.';
      final names = events
          .take(3)
          .map((e) => '${e.femaleName}, ${_formatDate(e.estimatedBirthDate)}')
          .join('; ');
      return 'Tienes ${events.length} eventos reproductivos registrados. Próximos datos: $names.';
    }
    return _upcomingEvents();
  }

  Future<String> _childrenList(String name, List<Rabbit> rabbits) async {
    final rabbit = _resolve(name, rabbits);
    if (rabbit == null) return _nameError(name, rabbits);
    final p = await _useCases.loadPedigree(rabbit.uuid);
    final children = p.descendants.where((a) => a.generation == -1).toList();
    if (children.isEmpty)
      return 'No hay hijos registrados para ${rabbit.name}.';
    return 'Los hijos de ${rabbit.name} son: ${children.map((a) => a.name).join(', ')}.';
  }

  Future<String> _hasDescendants(String name, List<Rabbit> rabbits) async {
    final rabbit = _resolve(name, rabbits);
    if (rabbit == null) return _nameError(name, rabbits);
    final p = await _useCases.loadPedigree(rabbit.uuid);
    final hasAny = p.descendants.any((a) => a.generation < 0);
    final descendants = p.descendants.where((a) => a.generation < 0).toList();
    if (!hasAny) return '${rabbit.name} no tiene descendientes registrados.';
    if (descendants.length == 1) {
      return 'Sí, ${rabbit.name} tiene un descendiente registrado: ${descendants.single.name}.';
    }
    return 'Sí, ${rabbit.name} tiene ${_spanishCount(descendants.length)} descendientes registrados.';
  }

  String _relationshipLabel(String raw) => switch (raw) {
        'FULL_SIBLINGS' || 'full_siblings' => 'hermanos completos',
        'HALF_SIBLINGS' || 'half_siblings' => 'medio hermanos',
        'PARENT_CHILD' || 'parent_child' => 'una relación de padre e hijo',
        'COUSINS' || 'cousins' => 'primos hermanos',
        'UNRELATED' || 'unrelated' => 'sin parentesco conocido',
        _ => 'un parentesco registrado',
      };

  String _formatNodes(String animal, List<PedigreeAnimal> nodes, String kind) {
    final names = nodes.take(8).map((a) => a.name).join(', ');
    final singular = nodes.length == 1;
    final count = switch (nodes.length) {
      1 => 'un',
      2 => 'dos',
      3 => 'tres',
      4 => 'cuatro',
      5 => 'cinco',
      6 => 'seis',
      7 => 'siete',
      8 => 'ocho',
      _ => nodes.length.toString(),
    };
    return '$animal tiene $count $kind${singular ? '' : 's'} registrado${singular ? '' : 's'}: $names.';
  }

  String _spanishCount(int value) => switch (value) {
        1 => 'un',
        2 => 'dos',
        3 => 'tres',
        4 => 'cuatro',
        5 => 'cinco',
        6 => 'seis',
        7 => 'siete',
        8 => 'ocho',
        _ => value.toString(),
      };

  String _percent(String? raw) {
    if (raw == null || raw.isEmpty) return 'no calculable';
    final value = double.tryParse(raw);
    if (value == null) return 'no calculable';
    final percent = value * 100;
    return '${percent.toStringAsFixed(percent == percent.roundToDouble() ? 0 : 2)} por ciento';
  }

  String _formatDate(String raw) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (match == null) return raw;
    const months = <String>[
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre'
    ];
    final month = int.parse(match.group(2)!);
    if (month < 1 || month > 12) return raw;
    return '${int.parse(match.group(3)!)} de ${months[month - 1]} de ${match.group(1)}';
  }

  Rabbit? _resolve(String query, List<Rabbit> rabbits) {
    final matches = rabbits
        .where((r) => r.name.trim().toLowerCase() == query.trim().toLowerCase())
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  String _nameError(String name, List<Rabbit> rabbits) {
    final matches = rabbits
        .where((r) => r.name.toLowerCase().contains(name.toLowerCase()))
        .length;
    return matches > 1
        ? 'Encontré varios conejos parecidos a $name. Di el nombre completo.'
        : 'No encontré un conejo llamado $name en tus registros.';
  }
}
