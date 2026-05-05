import '../../services/voice_commands.dart';
import '../engine/voice_ai_engine.dart';
import 'voice_intent_parser.dart';
import 'voice_orchestration.dart';

export '../engine/voice_ai_engine.dart'
    show VoiceAIEngine, VoiceAIResponse, VoiceNavigationAction;
export 'voice_intent_parser.dart';
export 'voice_orchestration.dart';

/// Orquestación: [VoiceIntentParser.parsePipeline] → motor; plan de efectos + habla.
///
/// No UI, sin red; la ejecución de efectos la hace el ViewModel.
class VoiceController {
  VoiceController({
    required VoiceIntentParser intentParser,
    required VoiceAIEngine aiEngine,
  })  : _intentParser = intentParser,
        _aiEngine = aiEngine;

  final VoiceIntentParser _intentParser;
  final VoiceAIEngine _aiEngine;

  VoiceIntent? _deferredIntentForSpeech;

  /// Último comando reconocido por [prepare], o `null` si no hubo coincidencia.
  VoiceCommand? lastParsedCommand;

  static const _unknownCmd =
      'No entendí el comando. Intenta decir: ver conejos o ver sensores';

  /// Construye el plan a partir del texto STT y la pestaña actual del shell.
  VoiceOrchestrationResult prepare(
    String recognizedText, {
    required int shellTabIndex,
  }) {
    _deferredIntentForSpeech = null;
    final trimmed = recognizedText.trim();
    if (trimmed.isEmpty) {
      lastParsedCommand = null;
      return const VoiceOrchestrationResult(effects: []);
    }

    final pipe = _intentParser.parsePipeline(trimmed);
    switch (pipe) {
      case VoicePipelineUnknown():
        lastParsedCommand = null;
        return const VoiceOrchestrationResult(
          effects: [],
          speech: _unknownCmd,
        );
      case VoicePipelineBadSlot(:final message, :final command):
        lastParsedCommand = command;
        return VoiceOrchestrationResult(
          effects: const [],
          speech: message,
        );
      case VoicePipelineOk(:final intent, :final command):
        lastParsedCommand = command;
        return _planForIntent(intent, shellTabIndex);
    }
  }

  /// Texto TTS tras efectos con carga (p. ej. [ListRabbitsIntent]).
  String? finishDeferredSpeech() {
    final i = _deferredIntentForSpeech;
    if (i == null) return null;
    return _aiEngine.resolve(i).textToSpeak;
  }

  VoiceOrchestrationResult _planForIntent(
      VoiceIntent intent, int shellTabIndex) {
    switch (intent) {
      case CreateRabbitIntent():
        return VoiceOrchestrationResult(
          effects: const [
            VoiceEffect(VoiceEffectType.openCreateRabbitScreen),
          ],
          speech: _aiEngine.resolve(intent).textToSpeak,
        );
      case ListRabbitsIntent():
        _deferredIntentForSpeech = intent;
        return const VoiceOrchestrationResult(
          effects: [
            VoiceEffect(VoiceEffectType.popToRoot),
            VoiceEffect(VoiceEffectType.changeTab, tabIndex: 0),
            VoiceEffect(VoiceEffectType.loadRabbits),
          ],
          deferredSpeech: true,
        );
      case ListRabbitsDetailedIntent():
        return VoiceOrchestrationResult(
          effects: [
            const VoiceEffect(VoiceEffectType.popToRoot),
            if (shellTabIndex != 0)
              const VoiceEffect(VoiceEffectType.changeTab, tabIndex: 0),
          ],
          speech: _aiEngine.resolve(intent).textToSpeak,
        );
      case OpenDashboardIntent():
        return VoiceOrchestrationResult(
          effects: const [
            VoiceEffect(VoiceEffectType.popToRoot),
            VoiceEffect(VoiceEffectType.changeTab, tabIndex: 1),
            VoiceEffect(VoiceEffectType.loadSensorReadings),
            VoiceEffect(VoiceEffectType.startSensorPolling),
          ],
          speech: _aiEngine.resolve(intent).textToSpeak,
        );
      case ShowSensorsIntent():
        return VoiceOrchestrationResult(
          effects: [
            const VoiceEffect(VoiceEffectType.popToRoot),
            if (shellTabIndex != 1)
              const VoiceEffect(VoiceEffectType.changeTab, tabIndex: 1),
            const VoiceEffect(VoiceEffectType.loadSensorReadings),
          ],
          speech: _aiEngine.resolve(intent).textToSpeak,
        );
      default:
        return VoiceOrchestrationResult(
          effects: const [],
          speech: _aiEngine.resolve(intent).textToSpeak,
        );
    }
  }
}
