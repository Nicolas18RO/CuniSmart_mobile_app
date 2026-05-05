import '../../core/state/async_view_state.dart';
import '../../models/rabbit.dart';
import '../../services/voice_commands.dart';
import '../../viewmodels/rabbit_viewmodel.dart';
import '../../viewmodels/sensor_viewmodel.dart';
import '../voice_speech_format.dart';

/// Acción de navegación sugerida por el motor; la ejecuta la capa MVVM / UI.
enum VoiceNavigationAction {
  /// Ir a la lista de conejos (pestaña principal).
  focusRabbitList,
}

/// Resultado puro del motor: texto para TTS y navegación opcional (no ejecutada aquí).
class VoiceAIResponse {
  const VoiceAIResponse({
    required this.textToSpeak,
    this.navigationAction,
  });

  final String textToSpeak;
  final VoiceNavigationAction? navigationAction;
}

/// Intents de alto nivel que el motor resuelve solo con datos en memoria.
sealed class VoiceIntent {}

/// Peso por nombre (token ya extraído del parser de voz).
final class WeightByNameIntent extends VoiceIntent {
  WeightByNameIntent(this.nameQuery);
  final String nameQuery;
}

/// Peso por id de conejo (memoria + eventos de sensor).
final class WeightByRabbitIdIntent extends VoiceIntent {
  WeightByRabbitIdIntent(this.rabbitId);
  final int rabbitId;
}

/// Lista simplificada de conejos registrados (solo texto).
final class ListRabbitsIntent extends VoiceIntent {
  ListRabbitsIntent();
}

/// Últimos eventos de peso desde sensores (mismo criterio que el comando de voz).
final class LatestWeightsIntent extends VoiceIntent {
  LatestWeightsIntent([this.requestedLimit]);
  final int? requestedLimit;
}

final class CreateRabbitIntent extends VoiceIntent {
  CreateRabbitIntent();
}

final class ListRabbitsDetailedIntent extends VoiceIntent {
  ListRabbitsDetailedIntent();
}

final class OpenDashboardIntent extends VoiceIntent {
  OpenDashboardIntent();
}

final class ShowSensorsIntent extends VoiceIntent {
  ShowSensorsIntent(this.readout);
  final VoiceSensorLexicalKind readout;
}

final class GetRabbitCountIntent extends VoiceIntent {
  GetRabbitCountIntent();
}

final class GetRabbitWeightHistoryIntent extends VoiceIntent {
  GetRabbitWeightHistoryIntent(this.rabbitId);
  final int rabbitId;
}

/// Capa de decisión de voz: sin [BuildContext], sin red, sin ejecutar navegación.
class VoiceAIEngine {
  VoiceAIEngine(this._rabbits, this._sensors);

  final RabbitViewModel _rabbits;
  final SensorViewModel _sensors;

  VoiceAIResponse resolve(VoiceIntent intent) {
    return switch (intent) {
      WeightByNameIntent(:final nameQuery) => _weightByName(nameQuery),
      WeightByRabbitIdIntent(:final rabbitId) => VoiceAIResponse(
          textToSpeak: _hierarchicalWeightText(rabbitId, _rabbitById(rabbitId)),
        ),
      ListRabbitsIntent() => _listRabbitsSimplified(),
      LatestWeightsIntent(:final requestedLimit) =>
        _latestWeights(requestedLimit),
      CreateRabbitIntent() => const VoiceAIResponse(
          textToSpeak: 'Perfecto, vamos a crear un nuevo conejo',
        ),
      ListRabbitsDetailedIntent() => _listRabbitsDetailed(),
      OpenDashboardIntent() => const VoiceAIResponse(
          textToSpeak: 'Aquí tienes el panel de sensores',
        ),
      ShowSensorsIntent(:final readout) => _showSensorsReadout(readout),
      GetRabbitCountIntent() => _rabbitCountSpeech(),
      GetRabbitWeightHistoryIntent(:final rabbitId) =>
        _rabbitWeightHistorySpeech(rabbitId),
    };
  }

  List<Rabbit> _rabbitsSnapshot() {
    final state = _rabbits.listState;
    return switch (state) {
      AsyncSuccess<List<Rabbit>>(:final data) => data,
      AsyncLoading<List<Rabbit>>(:final cachedData) =>
        cachedData ?? const <Rabbit>[],
      AsyncError<List<Rabbit>>(:final cachedData) =>
        cachedData ?? const <Rabbit>[],
      _ => const <Rabbit>[],
    };
  }

  Rabbit? _matchRabbitByName(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final r in _rabbitsSnapshot()) {
      if (r.name.trim().toLowerCase() == needle) return r;
    }
    for (final r in _rabbitsSnapshot()) {
      if (r.name.toLowerCase().contains(needle)) return r;
    }
    return null;
  }

  Rabbit? _rabbitById(int id) {
    for (final r in _rabbitsSnapshot()) {
      if (r.id == id) return r;
    }
    return null;
  }

  double? _latestSensorWeightForRabbit(int rabbitId) {
    for (final e in _sensors.weightEvents) {
      if (e.rabbitId == rabbitId && e.weight != null) {
        return e.weight;
      }
    }
    return null;
  }

  String _hierarchicalWeightText(int rabbitId, Rabbit? rabbit) {
    final sensorWeight = _latestSensorWeightForRabbit(rabbitId);
    final crudWeight = rabbit?.weight;
    final refForSensor = rabbit?.name ?? 'el conejo número $rabbitId';

    if (sensorWeight != null && crudWeight != null) {
      return 'El último peso del sensor para $refForSensor es '
          '${VoiceSpeechFormat.kgComma(sensorWeight)} kilogramos. '
          'Su peso registrado es de ${VoiceSpeechFormat.kgComma(crudWeight)}.';
    }
    if (rabbit != null && crudWeight != null) {
      return 'El conejo ${rabbit.name} tiene un peso registrado de '
          '${VoiceSpeechFormat.kgComma(crudWeight)} kilogramos.';
    }
    if (sensorWeight != null) {
      return 'El último peso del sensor para $refForSensor es '
          '${VoiceSpeechFormat.kgComma(sensorWeight)} kilogramos.';
    }
    return 'No hay información de peso disponible para este conejo.';
  }

  VoiceAIResponse _weightByName(String nameQuery) {
    final rabbit = _matchRabbitByName(nameQuery);
    if (rabbit == null) {
      return const VoiceAIResponse(
        textToSpeak: 'No encontré un conejo con ese nombre',
      );
    }
    return VoiceAIResponse(
        textToSpeak: _hierarchicalWeightText(rabbit.id, rabbit));
  }

  VoiceAIResponse _listRabbitsSimplified() {
    final list = _rabbitsSnapshot();
    if (list.isEmpty) {
      return const VoiceAIResponse(
        textToSpeak: 'No tienes conejos registrados en la lista.',
      );
    }
    const maxNames = 8;
    final names = list.take(maxNames).map((r) => r.name).toList();
    final extra = list.length > maxNames;
    final buf = StringBuffer('Tienes ${list.length} ');
    buf.write(list.length == 1 ? 'conejo registrado' : 'conejos registrados');
    buf.write(': ');
    buf.write(_joinSpanishList(names));
    if (extra) {
      buf.write(', y otros más');
    }
    buf.write('.');
    return VoiceAIResponse(textToSpeak: buf.toString());
  }

  String _joinSpanishList(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items[0];
    if (items.length == 2) return '${items[0]} y ${items[1]}';
    final head = items.sublist(0, items.length - 1).join(', ');
    return '$head y ${items.last}';
  }

  String _statusEs(String s) {
    switch (s) {
      case 'active':
        return 'activo';
      case 'sold':
        return 'vendido';
      case 'deceased':
        return 'fallecido';
      default:
        return s;
    }
  }

  String _describeRabbitForVoice(Rabbit r) {
    final peso = r.weight != null
        ? 'peso ${VoiceSpeechFormat.kgComma(r.weight!)} kilogramos'
        : 'sin peso registrado en la ficha';
    return '${r.name}, raza ${r.breed}, estado ${_statusEs(r.status)}, $peso';
  }

  VoiceAIResponse _listRabbitsDetailed() {
    final list = _rabbitsSnapshot();
    if (list.isEmpty) {
      return const VoiceAIResponse(
          textToSpeak: 'No tienes conejos registrados');
    }
    final limit = list.length > 3 ? 3 : list.length;
    final parts = <String>[];
    for (var i = 0; i < limit; i++) {
      parts.add(_describeRabbitForVoice(list[i]));
    }
    return VoiceAIResponse(textToSpeak: parts.join('. '));
  }

  VoiceAIResponse _showSensorsReadout(VoiceSensorLexicalKind readout) {
    switch (readout) {
      case VoiceSensorLexicalKind.temperature:
        final t = _sensors.latestRoomTemperature;
        if (t != null) {
          return VoiceAIResponse(
            textToSpeak:
                'La temperatura actual es ${VoiceSpeechFormat.doubleForSpeech(t)} grados',
          );
        }
        return const VoiceAIResponse(
          textToSpeak: 'Aún no hay datos de temperatura disponibles',
        );
      case VoiceSensorLexicalKind.water:
        final w = _sensors.latestTankWaterLevel;
        if (w != null) {
          return VoiceAIResponse(
            textToSpeak:
                'El nivel de agua es ${VoiceSpeechFormat.doubleForSpeech(w)} por ciento',
          );
        }
        return const VoiceAIResponse(
          textToSpeak: 'Aún no hay datos de agua disponibles',
        );
      case VoiceSensorLexicalKind.general:
        return const VoiceAIResponse(
          textToSpeak: 'Aquí tienes la información de los sensores',
        );
    }
  }

  VoiceAIResponse _rabbitCountSpeech() {
    final list = _rabbitsSnapshot();
    final count = list.length;
    if (count == 0) {
      return const VoiceAIResponse(
        textToSpeak: 'Aún no tienes conejos registrados',
      );
    }
    if (count == 1) {
      return const VoiceAIResponse(
        textToSpeak: 'Tienes un solo conejo registrado',
      );
    }
    return VoiceAIResponse(
      textToSpeak: 'Actualmente tienes $count conejos registrados',
    );
  }

  VoiceAIResponse _rabbitWeightHistorySpeech(int rabbitId) {
    final values = <double>[];
    for (final e in _sensors.weightEvents) {
      if (e.rabbitId != rabbitId) continue;
      final w = e.weight;
      if (w != null) values.add(w);
      if (values.length >= 3) break;
    }
    if (values.isEmpty) {
      return const VoiceAIResponse(
        textToSpeak: 'Aún no hay datos de peso disponibles para ese conejo',
      );
    }
    final formatted = values.map(VoiceSpeechFormat.kgComma).toList();
    final phrase = switch (formatted.length) {
      1 => formatted[0],
      2 => '${formatted[0]} y ${formatted[1]}',
      _ => '${formatted[0]}, ${formatted[1]} y ${formatted[2]}',
    };
    return VoiceAIResponse(
      textToSpeak:
          'Los últimos pesos del conejo $rabbitId son: $phrase kilogramos',
    );
  }

  /// Resumen de pesos en báscula: un solo evento **más reciente** por conejo (agrupa por [rabbitId]),
  /// solo conejos presentes en memoria; orden final por `createdAt` DESC.
  ///
  /// Si hay ≤3 conejos con datos → se listan todos. Si hay más → como mucho 3, los de
  /// registro global más reciente, sin superar el límite pedido por voz (máx. 3).
  VoiceAIResponse _latestWeights(int? requestedLimit) {
    final requested =
        (requestedLimit != null && requestedLimit > 0) ? requestedLimit : 3;
    final maxSlots = requested > 3 ? 3 : requested;

    final latestByRabbit = <int, ({String name, double weight, String createdAt})>{};
    for (final e in _sensors.weightEvents) {
      final rid = e.rabbitId;
      if (rid == null) continue;
      final weight = e.weight;
      if (weight == null) continue;
      if (latestByRabbit.containsKey(rid)) continue;
      final rabbit = _rabbitById(rid);
      if (rabbit == null) continue;
      latestByRabbit[rid] = (
        name: rabbit.name,
        weight: weight,
        createdAt: e.createdAt,
      );
    }

    if (latestByRabbit.isEmpty) {
      return const VoiceAIResponse(
        textToSpeak: 'No hay eventos de peso registrados',
      );
    }

    final entries = latestByRabbit.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final outCount =
        entries.length <= 3 ? entries.length : maxSlots.clamp(1, 3);

    final chosen = entries.take(outCount).toList();

    final partes = chosen
        .map(
          (row) =>
              '${row.name}: ${VoiceSpeechFormat.kgComma(row.weight)} kilogramos',
        )
        .toList();
    final frase = partes.join('. ');
    return VoiceAIResponse(
      textToSpeak: 'Los últimos pesos registrados son: $frase',
    );
  }
}
