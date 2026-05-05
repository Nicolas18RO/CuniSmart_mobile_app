import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/voice/app_voice_form_bridge.dart';
import '../services/voice_command_parser.dart';
import '../services/voice_commands.dart';
import '../services/voice_service.dart';
import '../voice/controller/voice_controller.dart';
import '../voice/form/voice_form_field.dart';
import '../voice/form/voice_form_field_assignment.dart';
import 'rabbit_viewmodel.dart';
import 'sensor_viewmodel.dart';

/// Orquestador liviano: STT/TTS + [VoiceController] + efectos de shell (sin reglas de dominio).
///
/// Push-to-talk: una sesión de escucha por activación del micrófono.
class VoiceViewModel extends ChangeNotifier {
  VoiceViewModel(
    this._voice,
    VoiceCommandParser voiceCommandParser,
    this._rabbits,
    this._sensors,
    this._voiceFormBridge, {
    VoidCallback? onRequestOpenCreateRabbitScreen,
    VoidCallback? onRequestPopToRoot,
    void Function(int index)? onChangeTab,
    void Function(String message)? onUiFeedback,
    int currentTabIndex = 0,
  })  : _onOpenCreate = onRequestOpenCreateRabbitScreen,
        _onPopToRoot = onRequestPopToRoot,
        _onChangeTab = onChangeTab,
        _onUiFeedback = onUiFeedback,
        _currentTabIndex = currentTabIndex {
    _voiceController = VoiceController(
      intentParser: VoiceIntentParser(voiceCommandParser),
      aiEngine: VoiceAIEngine(_rabbits, _sensors),
    );
    _voice.onSpeechStatus = _onEngineSpeechStatus;
  }

  late final VoiceController _voiceController;

  final VoiceService _voice;
  final RabbitViewModel _rabbits;
  final SensorViewModel _sensors;
  final AppVoiceFormBridge _voiceFormBridge;
  final VoidCallback? _onOpenCreate;
  final VoidCallback? _onPopToRoot;
  final void Function(int index)? _onChangeTab;
  final void Function(String message)? _onUiFeedback;

  int _currentTabIndex;

  int get currentTabIndex => _currentTabIndex;

  void updateCurrentTabIndex(int index) {
    if (index < 0 || index > 1) return;
    _currentTabIndex = index;
  }

  /// Limpia memoria de último comando TTS (p. ej. tras cerrar el flujo de alta por voz).
  void resetVoiceFormState() {
    lastRecognitionText = null;
    _lastCommandTextKey = null;
    _lastCommandTime = null;
    _lastSpokenTextKey = null;
    lastCommand = null;
  }

  /// Cierra rutas apiladas y fija la pestaña de lista de conejos (pantalla principal de conejos).
  void deactivateFormMode() {
    navigateToRabbitListScreen();
  }

  /// Raíz del navegador + pestaña conejos (lista principal).
  Future<void> navigateToRabbitListScreen() async {
    _onPopToRoot?.call();
    _onChangeTab?.call(0);
    updateCurrentTabIndex(0);
    notifyListeners();
  }

  /// Resetea estado de voz y borrador del formulario en el bridge.
  Future<void> hardResetVoiceState() async {
    resetVoiceFormState();
    _voiceFormBridge.hardReset();
  }

  /// Banderas del bridge (confirmación, etc.).
  Future<void> clearVoiceFormBridge() async {
    _voiceFormBridge.clear();
  }

  /// Deja el modo formulario a nivel de navegación (misma base que [navigateToRabbitListScreen]).
  Future<void> deactivateVoiceFormMode() async {
    await navigateToRabbitListScreen();
  }

  VoiceCommand? lastCommand;
  String? lastRecognitionText;

  bool _isProcessingCommand = false;
  bool _hasVoiceError = false;

  bool get isProcessing => _isProcessingCommand;

  bool get hasError => _hasVoiceError;

  bool get isVoiceModeEnabled => _voice.isListening;

  VoiceService get voice => _voice;

  VoiceFormMode get voiceFormMode => _voiceFormBridge.rabbitCreateRouteOpen
      ? VoiceFormMode.active
      : VoiceFormMode.inactive;

  bool _commandHandledThisSession = false;

  bool _silenceHandledThisSession = false;
  String? _lastSpokenTextKey;

  String? _lastCommandTextKey;
  DateTime? _lastCommandTime;

  int? _pendingDeleteRabbitId;
  String? _pendingDeleteDisplayName;

  void _resetListenSessionFlags() {
    _commandHandledThisSession = false;
    _silenceHandledThisSession = false;
  }

  void _onEngineSpeechStatus(String status) {
    if (status == SpeechToText.listeningStatus ||
        status == SpeechToText.notListeningStatus ||
        status == SpeechToText.doneStatus) {
      notifyListeners();
    }
  }

  Future<void> ensureVoiceReady() async {
    final ok = await _voice.ensureInitialized();
    _hasVoiceError = !ok;
    if (!kReleaseMode) {
      debugPrint('VoiceVM: ensureVoiceReady -> $ok');
    }
    if (!ok) {
      _onUiFeedback?.call(
        'No se pudo activar el micrófono. Revisa permisos de audio.',
      );
    }
    notifyListeners();
  }

  Future<void> toggleMicrophone() async {
    if (_voice.isListening) {
      await finalizeListeningSession();
    } else {
      await startListenSession();
    }
  }

  Future<void> startListenSession() async {
    if (_voice.isListening) {
      return;
    }
    _resetListenSessionFlags();
    _hasVoiceError = false;
    notifyListeners();

    await ensureVoiceReady();
    if (_hasVoiceError) {
      notifyListeners();
      return;
    }

    if (!_voice.isListening) {
      await _voice.startListening(
        onRecognitionResult: _onFinalRecognition,
      );
    }
    notifyListeners();
  }

  Future<void> finalizeListeningSession() async {
    if (!_voice.isListening) {
      return;
    }
    await _voice.stopListening();
    notifyListeners();

    if (_commandHandledThisSession) {
      return;
    }

    final recognized = _voice.lastRecognizedWords ?? '';
    final text = recognized.trim().toLowerCase();
    if (text.isEmpty) {
      if (_silenceHandledThisSession) return;
      _silenceHandledThisSession = true;
      if (!kReleaseMode) {
        debugPrint('VoiceVM: silence detected');
      }
      await speak('No escuché nada, intenta nuevamente');
    } else {
      _commandHandledThisSession = true;
      await applyCommandFromText(text);
    }
  }

  void _onFinalRecognition(SpeechRecognitionResult result) {
    if (!result.finalResult) {
      return;
    }
    unawaited(_runCommandFromFinalWords(result.recognizedWords));
  }

  Future<void> _runCommandFromFinalWords(String words) async {
    if (_commandHandledThisSession) {
      return;
    }

    final text = words.trim();
    if (text.isEmpty) {
      return;
    }

    _commandHandledThisSession = true;
    await applyCommandFromText(text);
  }

  Future<void> enableVoiceMode() async {
    await startListenSession();
  }

  Future<void> disableVoiceMode() async {
    await finalizeListeningSession();
  }

  Future<void> startListening() async {
    await startListenSession();
  }

  Future<void> stopListening() async {
    await finalizeListeningSession();
  }

  /// Alias requested by integration layer: normalize + route to [handleVoiceInput].
  Future<void> handleCommand(String command) async {
    final t = command.trim().toLowerCase();
    if (t.isEmpty) return;
    await handleVoiceInput(t);
  }

  String _commandLabel(VoiceCommand cmd) {
    return switch (cmd) {
      VoiceCommand.createRabbitVoiceForm => 'crear conejo',
      VoiceCommand.listRabbits => 'ver conejos',
      VoiceCommand.listRabbitsDetailed => 'ver conejos (detalle)',
      VoiceCommand.openDashboard => 'abrir panel',
      VoiceCommand.showSensors => 'ver sensores',
      VoiceCommand.getRabbitCount => 'contar conejos',
      VoiceCommand.getRabbitWeightById => 'peso por ID',
      VoiceCommand.getLatestWeightEvents => 'últimos pesos',
      VoiceCommand.getRabbitWeightHistory => 'historial de peso',
      VoiceCommand.weightByName => 'peso por nombre',
      VoiceCommand.deleteRabbitRequest => 'eliminar conejo',
      VoiceCommand.updateRabbitVoice => 'actualizar conejo',
      VoiceCommand.viewRabbitInfo => 'ver información',
    };
  }

  bool _shouldIgnoreDuplicateCommandText(String rawText) {
    final key = rawText.trim().toLowerCase();
    if (key.isEmpty) {
      return false;
    }
    final lastKey = _lastCommandTextKey;
    final lastAt = _lastCommandTime;
    if (lastKey == null || lastAt == null) {
      return false;
    }
    if (lastKey != key) {
      return false;
    }
    return DateTime.now().difference(lastAt) < const Duration(seconds: 2);
  }

  Future<void> speak(String text, {bool allowRepeat = false}) async {
    final t = text.trim();
    if (t.isEmpty) {
      return;
    }
    final key = t.toLowerCase();
    if (!allowRepeat && _lastSpokenTextKey == key) {
      return;
    }
    _lastSpokenTextKey = key;
    if (_voice.isListening) {
      await _voice.stopListening();
      notifyListeners();
    }
    await _voice.speak(t);
  }

  bool _isVoiceConfirmPhrase(String trimmedLower) {
    const phrases = {
      'confirmar',
      'confirma',
      'confirmo',
      'si',
      'sí',
      'de acuerdo',
      'ok',
      'vale',
    };
    final s = trimmedLower.trim();
    return phrases.contains(s);
  }

  bool _isVoiceCancelPhrase(String trimmedLower) {
    const phrases = {
      'cancelar',
      'cancela',
      'no',
      'abortar',
      'mejor no',
    };
    final s = trimmedLower.trim();
    return phrases.contains(s);
  }

  void _clearPendingDelete() {
    _pendingDeleteRabbitId = null;
    _pendingDeleteDisplayName = null;
  }

  Future<void> _handlePendingDeleteConfirm() async {
    if (_pendingDeleteRabbitId == null) return;
    if (_isProcessingCommand) return;
    _isProcessingCommand = true;
    notifyListeners();
    try {
      final id = _pendingDeleteRabbitId!;
      final name = _pendingDeleteDisplayName ?? '';
      _clearPendingDelete();
      final ok = await _rabbits.deleteRabbit(id);
      await speak(
        ok
            ? 'Listo, eliminé a $name.'
            : 'No pude eliminar al conejo. Intenta de nuevo.',
      );
      lastCommand = VoiceCommand.deleteRabbitRequest;
    } finally {
      _isProcessingCommand = false;
      notifyListeners();
    }
  }

  Future<void> _handlePendingDeleteCancel() async {
    if (_pendingDeleteRabbitId == null) return;
    if (_isProcessingCommand) return;
    _isProcessingCommand = true;
    notifyListeners();
    try {
      _clearPendingDelete();
      await speak('Eliminación cancelada.');
      lastCommand = null;
    } finally {
      _isProcessingCommand = false;
      notifyListeners();
    }
  }

  Future<void> _applySingleFillGuidance(List<VoiceFormFieldAssignment> fills) async {
    final g = _voiceFormBridge.applyRabbitCreateAssignmentsWithGuidance(fills);
    if (g != null && g.trim().isNotEmpty) {
      await speak(g);
    }
  }

  Future<void> _afterBurstVoiceFormApply() async {
    final speech = _voiceFormBridge.takeFinalReviewAndArmIfReady();
    if (speech != null && speech.trim().isNotEmpty) {
      await speak(speech);
    }
  }

  bool _isRabbitFormFinalConfirm(String trimmedLower) {
    const phrases = {
      'confirmar',
      'confirma',
      'confirmo',
      'si',
      'sí',
      'crear',
      'ok',
      'vale',
      'de acuerdo',
    };
    return phrases.contains(trimmedLower.trim());
  }

  bool _isRabbitFormFinalCancel(String trimmedLower) {
    const phrases = {
      'cancelar',
      'cancela',
      'no',
      'abortar',
      'mejor no',
    };
    return phrases.contains(trimmedLower.trim());
  }

  Future<void> _handleRabbitCreateFinalVoice(String lower) async {
    if (!_voiceFormBridge.isAwaitingFinalConfirmation) return;

    if (_isRabbitFormFinalConfirm(lower)) {
      final form = _voiceFormBridge.rabbitFormController;
      if (form == null || !form.readyForFinalVoiceConfirmation) {
        _voiceFormBridge.clearAwaitingFinalConfirmation();
        await speak('El formulario ya no está listo. Completa los datos de nuevo.');
        return;
      }

      _rabbits.clearSubmitError();

      final weightText = form.weight.text.trim();
      double? weight;
      if (weightText.isNotEmpty) {
        weight = double.tryParse(weightText.replaceAll(',', '.'));
      }

      final ok = await _rabbits.createRabbit(
        name: form.name.text.trim(),
        breed: form.breed.text.trim(),
        sex: form.sex,
        birthDate: form.birthDate.text.trim(),
        weight: weight,
        status: form.status,
        notes: form.notes.text.trim(),
      );

      if (ok) {
        await _afterSuccessfulVoiceCreate();
      } else {
        await speak(
          'No pude crear el conejo. Revisa los datos o inténtalo otra vez. '
          'Di confirmar cuando esté corregido, o cancelar.',
          allowRepeat: true,
        );
      }
      return;
    }

    if (_isRabbitFormFinalCancel(lower)) {
      _voiceFormBridge.clearAwaitingFinalConfirmation();
      await speak('Creación cancelada.');
      lastCommand = null;
      return;
    }

    await speak(
      'No entendí. Di confirmar o cancelar.',
      allowRepeat: true,
    );
  }

  Future<void> _afterSuccessfulVoiceCreate() async {
    await hardResetVoiceState();
    await navigateToRabbitListScreen();
    await Future<void>.delayed(Duration.zero);
    await clearVoiceFormBridge();
    await speak('Conejo creado correctamente.');
  }

  Future<void> _applyVoiceEffects(List<VoiceEffect> effects) async {
    for (final e in effects) {
      switch (e.type) {
        case VoiceEffectType.popToRoot:
          _onPopToRoot?.call();
          break;
        case VoiceEffectType.changeTab:
          final i = e.tabIndex;
          if (i != null) _onChangeTab?.call(i);
          break;
        case VoiceEffectType.loadRabbits:
          await _rabbits.loadRabbits();
          break;
        case VoiceEffectType.loadSensorReadings:
          await _sensors.loadSensorReadings();
          break;
        case VoiceEffectType.startSensorPolling:
          _sensors.startPolling();
          break;
        case VoiceEffectType.openCreateRabbitScreen:
          final open = _onOpenCreate;
          if (open != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => open());
          }
          break;
      }
    }
  }

  Future<void> _applyRabbitVoiceCrud(VoiceOrchestrationResult plan) async {
    if (plan.pendingDelete != null) {
      _pendingDeleteRabbitId = plan.pendingDelete!.rabbitId;
      _pendingDeleteDisplayName = plan.pendingDelete!.displayName;
      notifyListeners();
      return;
    }

    final u = plan.updateByVoice;
    if (u != null) {
      final s = u.snapshot;
      final ok = await _rabbits.updateRabbit(
        id: s.id,
        name: s.name,
        breed: s.breed,
        sex: s.sex,
        birthDate: s.birthDate,
        weight: u.newWeight,
        status: s.status,
        notes: s.notes,
      );
      await speak(
        ok
            ? 'Listo, actualicé el peso de ${s.name}.'
            : 'No pude actualizar al conejo.',
      );
    }
  }

  /// Flujo: texto STT → [VoiceController] → efectos → TTS.
  Future<void> handleVoiceInput(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final lower = trimmed.toLowerCase();

    if (_pendingDeleteRabbitId != null) {
      if (_isVoiceConfirmPhrase(lower)) {
        await _handlePendingDeleteConfirm();
        return;
      }
      if (_isVoiceCancelPhrase(lower)) {
        await _handlePendingDeleteCancel();
        return;
      }
    }

    if (_voiceFormBridge.isAwaitingFinalConfirmation) {
      if (_isProcessingCommand) {
        return;
      }
      _isProcessingCommand = true;
      notifyListeners();
      try {
        lastRecognitionText = text;
        await _handleRabbitCreateFinalVoice(lower);
      } finally {
        _isProcessingCommand = false;
        notifyListeners();
      }
      return;
    }

    if (_shouldIgnoreDuplicateCommandText(text)) {
      return;
    }

    if (_isProcessingCommand) {
      return;
    }
    _isProcessingCommand = true;
    notifyListeners();

    try {
      lastRecognitionText = text;
      final plan = _voiceController.prepare(
        trimmed,
        shellTabIndex: _currentTabIndex,
        rabbitFormSnapshot: _voiceFormBridge.readRabbitCreateSnapshot(),
      );
      lastCommand = _voiceController.lastParsedCommand;

      final fb = _onUiFeedback;
      if (fb != null) {
        if (lastCommand == null) {
          fb('No se entendió el comando.');
        } else {
          fb('Comando reconocido: ${_commandLabel(lastCommand!)}');
        }
      }

      if (_pendingDeleteRabbitId != null &&
          lastCommand != null &&
          lastCommand != VoiceCommand.deleteRabbitRequest) {
        _clearPendingDelete();
      }

      notifyListeners();

      await _applyVoiceEffects(plan.effects);

      final toSpeak = plan.deferredSpeech
          ? _voiceController.finishDeferredSpeech()
          : plan.speech;

      if (lastCommand != null) {
        _lastCommandTextKey = trimmed.toLowerCase();
        _lastCommandTime = DateTime.now();
      }

      if (toSpeak != null && toSpeak.trim().isNotEmpty) {
        await speak(toSpeak);
      }

      final fills = plan.rabbitCreateFormFills;
      if (fills != null && fills.isNotEmpty) {
        if (fills.length > 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _voiceFormBridge.applyRabbitCreateAssignments(fills);
            unawaited(_afterBurstVoiceFormApply());
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(_applySingleFillGuidance(fills));
          });
        }
      }

      await _applyRabbitVoiceCrud(plan);

      if (!kReleaseMode) {
        debugPrint('VoiceVM: handleVoiceInput cmd=$lastCommand');
      }
    } finally {
      _isProcessingCommand = false;
      notifyListeners();
    }
  }

  /// Compatibilidad con llamadas existentes (mic / debug); delega en [handleVoiceInput].
  Future<void> applyCommandFromText(String text) async {
    await handleVoiceInput(text);
  }

  Future<void> applyLastRecognition() async {
    final text = _voice.lastRecognizedWords ?? '';
    await applyCommandFromText(text);
  }

  @override
  void dispose() {
    _voice.onSpeechStatus = null;
    super.dispose();
  }
}
