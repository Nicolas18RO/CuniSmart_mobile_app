import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/voice_command_parser.dart';
import '../services/voice_commands.dart';
import '../services/voice_service.dart';
import '../voice/controller/voice_controller.dart';
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
    this._sensors, {
    VoidCallback? onRequestOpenCreateRabbitScreen,
    VoidCallback? onRequestPopToRoot,
    void Function(int index)? onChangeTab,
    int currentTabIndex = 0,
  })  : _onOpenCreate = onRequestOpenCreateRabbitScreen,
        _onPopToRoot = onRequestPopToRoot,
        _onChangeTab = onChangeTab,
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
  final VoidCallback? _onOpenCreate;
  final VoidCallback? _onPopToRoot;
  final void Function(int index)? _onChangeTab;

  int _currentTabIndex;

  int get currentTabIndex => _currentTabIndex;

  void updateCurrentTabIndex(int index) {
    if (index < 0 || index > 1) return;
    _currentTabIndex = index;
  }

  VoiceCommand? lastCommand;
  String? lastRecognitionText;

  bool _isProcessingCommand = false;
  bool _hasVoiceError = false;

  bool get isProcessing => _isProcessingCommand;

  bool get hasError => _hasVoiceError;

  bool get isVoiceModeEnabled => _voice.isListening;

  VoiceService get voice => _voice;

  bool _commandHandledThisSession = false;

  bool _silenceHandledThisSession = false;
  String? _lastSpokenTextKey;

  String? _lastCommandTextKey;
  DateTime? _lastCommandTime;

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

  Future<void> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) {
      return;
    }
    final key = t.toLowerCase();
    if (_lastSpokenTextKey == key) {
      return;
    }
    _lastSpokenTextKey = key;
    if (_voice.isListening) {
      await _voice.stopListening();
      notifyListeners();
    }
    await _voice.speak(t);
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
          _onOpenCreate?.call();
          break;
      }
    }
  }

  /// Flujo: texto STT → [VoiceController] → efectos → TTS.
  Future<void> handleVoiceInput(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
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
      );
      lastCommand = _voiceController.lastParsedCommand;
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
