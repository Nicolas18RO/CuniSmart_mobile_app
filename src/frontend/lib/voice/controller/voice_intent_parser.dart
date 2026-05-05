import '../../services/voice_command_parser.dart';
import '../../services/voice_commands.dart';
import '../engine/voice_ai_engine.dart';

sealed class VoicePipelineResult {}

/// Frase sin comando reconocido.
final class VoicePipelineUnknown extends VoicePipelineResult {
  VoicePipelineUnknown();
}

/// Comando reconocido pero falta un dato (id, nombre, etc.).
final class VoicePipelineBadSlot extends VoicePipelineResult {
  VoicePipelineBadSlot(this.message, this.command);
  final String message;
  final VoiceCommand command;
}

/// Comando + intent listos para el motor.
final class VoicePipelineOk extends VoicePipelineResult {
  VoicePipelineOk({required this.intent, required this.command});
  final VoiceIntent intent;
  final VoiceCommand command;
}

sealed class _SlotParseResult {}

final class _SlotParseBad extends _SlotParseResult {
  _SlotParseBad(this.message);
  final String message;
}

final class _SlotParseOk extends _SlotParseResult {
  _SlotParseOk(this.intent);
  final VoiceIntent intent;
}

/// Una sola pasada: [VoiceCommandParser.parse] → [VoiceIntent] (payloads para el motor).
///
/// No ejecuta efectos, TTS ni accede a ViewModels.
class VoiceIntentParser {
  VoiceIntentParser(this._commandParser);

  final VoiceCommandParser _commandParser;

  /// Única entrada de clasificación + extracción de slots para el pipeline de voz.
  VoicePipelineResult parsePipeline(String recognizedText) {
    final trimmed = recognizedText.trim();
    if (trimmed.isEmpty) {
      return VoicePipelineUnknown();
    }

    // Prioridad 1: consulta de ficha (antes que peso, alta, etc.).
    final viewName = _commandParser.extractViewRabbitInfoNameQuery(trimmed);
    if (viewName != null && viewName.trim().isNotEmpty) {
      return VoicePipelineOk(
        intent: ViewRabbitInfoIntent(viewName.trim()),
        command: VoiceCommand.viewRabbitInfo,
      );
    }

    final cmd = _commandParser.parse(trimmed);
    if (cmd == null) {
      return VoicePipelineUnknown();
    }
    return switch (_intentFrom(trimmed, cmd)) {
      _SlotParseBad(:final message) => VoicePipelineBadSlot(message, cmd),
      _SlotParseOk(:final intent) =>
        VoicePipelineOk(intent: intent, command: cmd),
    };
  }

  _SlotParseResult _intentFrom(String recognizedText, VoiceCommand cmd) {
    switch (cmd) {
      case VoiceCommand.weightByName:
        final name = _commandParser.extractRabbitName(recognizedText);
        if (name == null) {
          return _SlotParseBad('No entendí el nombre');
        }
        return _SlotParseOk(WeightByNameIntent(name));
      case VoiceCommand.getRabbitWeightById:
        final id = _commandParser.extractRabbitId(recognizedText);
        if (id == null) {
          return _SlotParseBad('No entendí el número del conejo');
        }
        return _SlotParseOk(WeightByRabbitIdIntent(id));
      case VoiceCommand.listRabbits:
        return _SlotParseOk(ListRabbitsIntent());
      case VoiceCommand.getLatestWeightEvents:
        final limit = _commandParser.extractLatestWeightLimit(recognizedText);
        return _SlotParseOk(LatestWeightsIntent(limit));
      case VoiceCommand.getRabbitWeightHistory:
        final id = _commandParser.extractRabbitId(recognizedText);
        if (id == null) {
          return _SlotParseBad('No entendí el número del conejo');
        }
        return _SlotParseOk(GetRabbitWeightHistoryIntent(id));
      case VoiceCommand.listRabbitsDetailed:
        return _SlotParseOk(ListRabbitsDetailedIntent());
      case VoiceCommand.openDashboard:
        return _SlotParseOk(OpenDashboardIntent());
      case VoiceCommand.showSensors:
        return _SlotParseOk(
          ShowSensorsIntent(
            _commandParser.lexicalSensorReadout(recognizedText),
          ),
        );
      case VoiceCommand.getRabbitCount:
        return _SlotParseOk(GetRabbitCountIntent());
      case VoiceCommand.deleteRabbitRequest:
        final q = _commandParser.extractDeleteRabbitNameQuery(recognizedText);
        if (q == null) {
          return _SlotParseBad('Di el nombre del conejo que quieres eliminar.');
        }
        return _SlotParseOk(DeleteRabbitRequestIntent(q));
      case VoiceCommand.updateRabbitVoice:
        final q = _commandParser.extractUpdateRabbitNameQuery(recognizedText);
        if (q == null) {
          return _SlotParseBad('Di el nombre del conejo que quieres editar.');
        }
        final w = _commandParser.extractVoiceWeightAfterPeso(recognizedText);
        return _SlotParseOk(UpdateRabbitVoiceIntent(q, newWeight: w));
      case VoiceCommand.viewRabbitInfo:
        final q = _commandParser.extractViewRabbitInfoNameQuery(recognizedText);
        if (q == null) {
          return _SlotParseBad(
            'Di por ejemplo: información de, y el nombre del conejo.',
          );
        }
        return _SlotParseOk(ViewRabbitInfoIntent(q));
      case VoiceCommand.createRabbitVoiceForm:
        final rem =
            _commandParser.extractCreateRabbitVoiceFormRemainder(recognizedText);
        return _SlotParseOk(CreateRabbitVoiceFormIntent(rem));
    }
  }
}
