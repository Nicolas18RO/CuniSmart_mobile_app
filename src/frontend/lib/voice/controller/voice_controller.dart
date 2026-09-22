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
    final snap = rabbitFormSnapshot;

    if (snap != null && snap.routeOpen) {
      return _prepareWhileFormOpen(trimmed, snap, shellTabIndex);
    }

    if (trimmed.isEmpty) {
      lastParsedCommand = null;
      return const VoiceOrchestrationResult(effects: []);
    }

    final pipe = _intentParser.parsePipeline(trimmed);
    return _orchestratePipeline(pipe, shellTabIndex);
  }

  /// Formulario activo: controles transversales → campo → sin parser global de nav.
  VoiceOrchestrationResult _prepareWhileFormOpen(
    String trimmed,
    RabbitCreateVoiceFormSnapshot snap,
    int shellTabIndex,
  ) {
    if (trimmed.isEmpty) {
      lastParsedCommand = null;
      return VoiceOrchestrationResult(
        effects: const [],
        speech: RabbitCreateVoiceFormGuidance.emptySttWhileForm(),
        shouldRestartListening: true,
      );
    }

    final lower = trimmed.toLowerCase();

    if (_isFormCancelPhrase(lower)) {
      lastParsedCommand = null;
      return const VoiceOrchestrationResult(
        effects: [VoiceEffect(VoiceEffectType.cancelCreateRabbitForm)],
        speech: 'Creación cancelada.',
      );
    }

    if (_isFormRepeatPhrase(lower)) {
      lastParsedCommand = null;
      return VoiceOrchestrationResult(
        effects: const [],
        speech: RabbitCreateVoiceFormGuidance.promptForField(snap.activeVoiceField),
        shouldRestartListening: true,
      );
    }

    if (_isFormHelpPhrase(lower)) {
      lastParsedCommand = null;
      return VoiceOrchestrationResult(
        effects: const [],
        speech: RabbitCreateVoiceFormGuidance.helpForField(snap.activeVoiceField),
        shouldRestartListening: true,
      );
    }

    final correctionTarget = _parseCorrectionField(lower);
    if (correctionTarget != null) {
      lastParsedCommand = null;
      return VoiceOrchestrationResult(
        effects: const [],
        speech: RabbitCreateVoiceFormGuidance.correctionPrompt(correctionTarget),
        shouldRestartListening: true,
        correctFormField: correctionTarget,
      );
    }

    final pipe = _intentParser.parsePipeline(trimmed);

    // «crear/registrar conejo …» con datos: se mantiene el flujo de ráfaga.
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
      return VoiceOrchestrationResult(
        effects: const [],
        speech: message,
        shouldRestartListening: true,
      );
    }

    // Cualquier otro comando global (ver sensores, lista, etc.): contexto, sin nav.
    if (pipe case VoicePipelineOk()) {
      lastParsedCommand = null;
      return VoiceOrchestrationResult(
        effects: const [],
        speech: RabbitCreateVoiceFormGuidance.contextualBusyForField(
          snap.activeVoiceField,
        ),
        shouldRestartListening: true,
      );
    }

    return _voiceFormFieldContinuation(trimmed, snap);
  }

  static bool _isFormCancelPhrase(String lower) {
    final s = lower.trim();
    return s == 'cancelar' ||
        s == 'cancela' ||
        s == 'abortar' ||
        s == 'salir del formulario' ||
        s == 'cancelar creación' ||
        s == 'cancelar creacion';
  }

  static bool _isFormRepeatPhrase(String lower) {
    final s = lower.trim();
    return s == 'repetir' ||
        s == 'repítelo' ||
        s == 'repitelo' ||
        s == 'otra vez' ||
        s == 'repite';
  }

  static bool _isFormHelpPhrase(String lower) {
    final s = lower.trim();
    return s == 'ayuda' ||
        s == 'qué digo' ||
        s == 'que digo' ||
        s == 'qué debo decir' ||
        s == 'que debo decir';
  }

  /// «corregir|cambiar|modificar …» → campo del alta (solo creación local).
  static VoiceFormField? _parseCorrectionField(String lower) {
    final s = lower.trim();
    final m = RegExp(
      r'^(?:quiero\s+)?(?:corregir|cambiar|cambia|modificar|modifica)\s+'
      r'(?:la\s+|el\s+)?'
      r'(nombre|raza|sexo|fecha(?:\s+de\s+nacimiento)?|peso|estado|notas)\s*$',
    ).firstMatch(s);
    if (m == null) return null;
    final raw = m.group(1)!;
    if (raw.startsWith('fecha')) return VoiceFormField.birthDate;
    return switch (raw) {
      'nombre' => VoiceFormField.name,
      'raza' => VoiceFormField.breed,
      'sexo' => VoiceFormField.sex,
      'peso' => VoiceFormField.weight,
      'estado' => VoiceFormField.status,
      'notas' => VoiceFormField.notes,
      _ => null,
    };
  }

  /// Solo parser de campos (todos los ASKING_*); sin efectos shell.
  VoiceOrchestrationResult _voiceFormFieldContinuation(
    String trimmed,
    RabbitCreateVoiceFormSnapshot snap,
  ) {
    if (RabbitCreateVoiceFormParser.isNonFormChatter(trimmed)) {
      lastParsedCommand = null;
      return VoiceOrchestrationResult(
        effects: const [],
        speech: RabbitCreateVoiceFormGuidance.helpForField(snap.activeVoiceField),
        shouldRestartListening: true,
      );
    }
    final fills = RabbitCreateVoiceFormParser.parseContinuation(trimmed, snap);
    if (fills.isEmpty) {
      lastParsedCommand = null;
      return VoiceOrchestrationResult(
        effects: const [],
        speech: RabbitCreateVoiceFormGuidance.unrecognizedForField(
          snap.activeVoiceField,
        ),
        shouldRestartListening: true,
      );
    }
    lastParsedCommand = null;
    return VoiceOrchestrationResult(
      effects: const [],
      rabbitCreateFormFills: fills,
      // Tras confirmar un campo, el VM habla la guía y debe volver a escuchar.
      shouldRestartListening: true,
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
      shouldRestartListening: true,
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
                  rabbitUuid: rabbit.uuid,
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
