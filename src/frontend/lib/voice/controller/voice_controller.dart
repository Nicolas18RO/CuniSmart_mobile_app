import '../../services/voice_commands.dart';
import '../engine/voice_ai_engine.dart';
import '../form/rabbit_create_voice_form_guidance.dart';
import '../form/rabbit_create_voice_form_parser.dart';
import '../form/rabbit_create_voice_form_snapshot.dart';
import '../form/voice_form_field.dart';
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

  static const List<VoiceEffect> _rabbitTabEffects = [
    VoiceEffect(VoiceEffectType.popToRoot),
    VoiceEffect(VoiceEffectType.changeTab, tabIndex: 0),
    VoiceEffect(VoiceEffectType.loadRabbits),
  ];

  /// Último comando reconocido por [prepare], o `null` si no hubo coincidencia.
  VoiceCommand? lastParsedCommand;

  static const _unknownCmd =
      'No entendí el comando. Intenta decir: ver conejos o ver sensores';

  /// Construye el plan a partir del texto STT y la pestaña actual del shell.
  VoiceOrchestrationResult prepare(
    String recognizedText, {
    required int shellTabIndex,
    RabbitCreateVoiceFormSnapshot? rabbitFormSnapshot,
  }) {
    _deferredIntentForSpeech = null;
    final trimmed = recognizedText.trim();
    if (trimmed.isEmpty) {
      lastParsedCommand = null;
      return const VoiceOrchestrationResult(effects: []);
    }

    final snap = rabbitFormSnapshot;
    if (snap != null && snap.routeOpen) {
      // Texto libre (nombre, raza, notas) suele contener «conejo» → el parser global
      // puede clasificar listRabbits / otros intents y disparar navegación.
      // Solo relleno del campo, sin VoiceIntentParser ni efectos shell.
      final af = snap.activeVoiceField;
      if (af == VoiceFormField.name ||
          af == VoiceFormField.breed ||
          af == VoiceFormField.notes) {
        return _voiceFormFieldContinuation(trimmed, snap);
      }
      final pipe = _intentParser.parsePipeline(trimmed);
      // Cualquier comando distinto de «crear/registrar/agregar conejo» (p. ej.
      // viewRabbitInfo, listar, peso…) sale del modo formulario guiado.
      if (pipe case VoicePipelineOk(:final command)) {
        if (command != VoiceCommand.createRabbitVoiceForm) {
          return _orchestratePipeline(pipe, shellTabIndex);
        }
      }
      if (pipe case VoicePipelineOk(
            :final intent,
            :final command,
          )
          when command == VoiceCommand.createRabbitVoiceForm &&
              intent is CreateRabbitVoiceFormIntent) {
        lastParsedCommand = command;
        return _planCreateRabbitVoiceForm(intent, shellTabIndex);
      }
      if (pipe case VoicePipelineBadSlot(:final message, :final command)) {
        lastParsedCommand = command;
        return VoiceOrchestrationResult(effects: const [], speech: message);
      }
      if (pipe case VoicePipelineUnknown()) {
        if (RabbitCreateVoiceFormParser.isNonFormChatter(trimmed)) {
          lastParsedCommand = null;
          return const VoiceOrchestrationResult(
            effects: [],
            speech:
                'Eso no es un dato del formulario. Sigue la indicación o di el valor pedido.',
          );
        }
        final fills = RabbitCreateVoiceFormParser.parseContinuation(trimmed, snap);
        if (fills.isEmpty) {
          lastParsedCommand = null;
          return const VoiceOrchestrationResult(
            effects: [],
            speech: 'No entendí. Repite o completa el campo.',
          );
        }
        lastParsedCommand = null;
        return VoiceOrchestrationResult(
          effects: const [],
          rabbitCreateFormFills: fills,
        );
      }
    }

    final pipe = _intentParser.parsePipeline(trimmed);
    return _orchestratePipeline(pipe, shellTabIndex);
  }

  /// Sin [VoiceIntentParser]: solo parser de campos (paso notas u otros texto libre).
  VoiceOrchestrationResult _voiceFormFieldContinuation(
    String trimmed,
    RabbitCreateVoiceFormSnapshot snap,
  ) {
    if (RabbitCreateVoiceFormParser.isNonFormChatter(trimmed)) {
      lastParsedCommand = null;
      return const VoiceOrchestrationResult(
        effects: [],
        speech:
            'Eso no es un dato del formulario. Sigue la indicación o di el valor pedido.',
      );
    }
    final fills = RabbitCreateVoiceFormParser.parseContinuation(trimmed, snap);
    if (fills.isEmpty) {
      lastParsedCommand = null;
      final hint = snap.activeVoiceField == VoiceFormField.notes
          ? 'No entendí. Di tus notas o di sin notas.'
          : 'No entendí. Repite o completa el campo.';
      return VoiceOrchestrationResult(effects: const [], speech: hint);
    }
    lastParsedCommand = null;
    return VoiceOrchestrationResult(
      effects: const [],
      rabbitCreateFormFills: fills,
    );
  }

  VoiceOrchestrationResult _orchestratePipeline(
    VoicePipelineResult pipe,
    int shellTabIndex,
  ) {
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

  VoiceOrchestrationResult _planCreateRabbitVoiceForm(
    CreateRabbitVoiceFormIntent intent,
    int shellTabIndex,
  ) {
    final fills =
        RabbitCreateVoiceFormParser.parseBurst(intent.remainderAfterPrefix);
    // Siempre lista + push de la ruta: evita modo voz sin pantalla (bridge antiguo).
    final effects = <VoiceEffect>[
      ..._rabbitTabEffects,
      const VoiceEffect(VoiceEffectType.openCreateRabbitScreen),
    ];
    final engineLine = _aiEngine.resolve(intent).textToSpeak.trim();
    final String? speech;
    if (fills.length > 1) {
      speech = RabbitCreateVoiceFormGuidance.forBurst(fills);
    } else if (fills.length == 1) {
      speech = engineLine.isEmpty ? null : engineLine;
    } else {
      speech = engineLine.isEmpty ? null : engineLine;
    }
    return VoiceOrchestrationResult(
      effects: effects,
      speech: speech,
      rabbitCreateFormFills: fills.isEmpty ? null : fills,
    );
  }

  VoiceOrchestrationResult _planForIntent(
    VoiceIntent intent,
    int shellTabIndex,
  ) {
    switch (intent) {
      case ViewRabbitInfoIntent():
        _deferredIntentForSpeech = intent;
        return const VoiceOrchestrationResult(
          effects: [
            VoiceEffect(VoiceEffectType.popToRoot),
            VoiceEffect(VoiceEffectType.changeTab, tabIndex: 0),
            VoiceEffect(VoiceEffectType.loadRabbits),
          ],
          deferredSpeech: true,
        );
      case CreateRabbitVoiceFormIntent():
        return _planCreateRabbitVoiceForm(intent, shellTabIndex);
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
      case DeleteRabbitRequestIntent(:final nameQuery):
        final rabbit = _aiEngine.rabbitMatchingVoiceName(nameQuery);
        final speech =
            _aiEngine.resolve(DeleteRabbitRequestIntent(nameQuery)).textToSpeak;
        return VoiceOrchestrationResult(
          effects: const [
            VoiceEffect(VoiceEffectType.popToRoot),
            VoiceEffect(VoiceEffectType.changeTab, tabIndex: 0),
            VoiceEffect(VoiceEffectType.loadRabbits),
          ],
          speech: speech,
          pendingDelete: rabbit == null
              ? null
              : VoicePendingDelete(
                  rabbitId: rabbit.id,
                  displayName: rabbit.name,
                ),
        );
      case UpdateRabbitVoiceIntent(:final nameQuery, :final newWeight):
        final rabbit = _aiEngine.rabbitMatchingVoiceName(nameQuery);
        final speech = _aiEngine
            .resolve(UpdateRabbitVoiceIntent(nameQuery, newWeight: newWeight))
            .textToSpeak;
        return VoiceOrchestrationResult(
          effects: const [
            VoiceEffect(VoiceEffectType.popToRoot),
            VoiceEffect(VoiceEffectType.changeTab, tabIndex: 0),
            VoiceEffect(VoiceEffectType.loadRabbits),
          ],
          speech: speech,
          updateByVoice: rabbit != null && newWeight != null
              ? VoiceUpdateByVoicePayload(
                  snapshot: rabbit,
                  newWeight: newWeight,
                )
              : null,
        );
      default:
        return VoiceOrchestrationResult(
          effects: const [],
          speech: _aiEngine.resolve(intent).textToSpeak,
        );
    }
  }
}
