import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/voice_command_parser.dart';
import '../services/voice_commands.dart';
import '../services/voice_service.dart';
import 'rabbit_viewmodel.dart';
import 'sensor_viewmodel.dart';

enum _SensorVoiceSubIntent { temperature, water, general }

/// Bridges [VoiceService] + [VoiceCommandParser] to [RabbitViewModel] / [SensorViewModel].
///
/// Push-to-talk: one listening session per mic activation; no automatic re-listening.
class VoiceViewModel extends ChangeNotifier {
  VoiceViewModel(
    this._voice,
    this._parser,
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
    _voice.onSpeechStatus = _onEngineSpeechStatus;
  }

  final VoiceService _voice;
  final VoiceCommandParser _parser;
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

  /// True while a parsed command is running (including TTS from commands).
  bool get isProcessing => _isProcessingCommand;

  /// True if the last [startListenSession] could not initialize STT.
  bool get hasError => _hasVoiceError;

  /// Alias for UI: STT session active.
  bool get isVoiceModeEnabled => _voice.isListening;

  VoiceService get voice => _voice;

  /// One voice command (or silence feedback) per listen session.
  bool _commandHandledThisSession = false;

  bool _silenceHandledThisSession = false;

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

  /// Mic on: start one STT session. Mic off: [finalizeListeningSession].
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

  /// User stopped listening early or session ended; apply last text if needed.
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

  String? _lastCommandTextKey;
  DateTime? _lastCommandTime;

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
    if (_voice.isListening) {
      await _voice.stopListening();
      notifyListeners();
    }
    await _voice.speak(t);
  }

  Future<void> applyCommandFromText(String text) async {
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
      final cmd = _parser.parse(text);
      lastCommand = cmd;
      notifyListeners();

      if (cmd == null) {
        await speak(
          'No entendí el comando. Intenta decir: ver conejos o ver sensores',
        );
        return;
      }

      _lastCommandTextKey = trimmed.toLowerCase();
      _lastCommandTime = DateTime.now();

      await _execute(cmd);
      if (!kReleaseMode) {
        debugPrint('VoiceVM: command executed cmd=$cmd');
      }
    } finally {
      _isProcessingCommand = false;
      notifyListeners();
    }
  }

  Future<void> applyLastRecognition() async {
    final text = _voice.lastRecognizedWords ?? '';
    await applyCommandFromText(text);
  }

  Future<void> _execute(VoiceCommand cmd) async {
    switch (cmd) {
      case VoiceCommand.createRabbit:
        _onOpenCreate?.call();
        await speak('Creando nuevo conejo');
        break;
      case VoiceCommand.listRabbits:
        _onPopToRoot?.call();
        if (_currentTabIndex == 0) {
          await _rabbits.loadRabbits();
          await speak('Actualizando lista de conejos');
        } else {
          _onChangeTab?.call(0);
          await _rabbits.loadRabbits();
          await speak('Abriendo conejos');
        }
        break;
      case VoiceCommand.openDashboard:
        _onPopToRoot?.call();
        _onChangeTab?.call(1);
        await _sensors.loadSensorReadings();
        _sensors.startPolling();
        await speak('Mostrando panel IoT');
        break;
      case VoiceCommand.showSensors:
        await _executeShowSensors();
        break;
    }
  }

  static final _voiceWordPattern = RegExp(r'\p{L}+', unicode: true);

  _SensorVoiceSubIntent _sensorSubIntentFromLastPhrase() {
    final raw = lastRecognitionText ?? '';
    final words = _voiceWordPattern
        .allMatches(raw.toLowerCase())
        .map((m) => m.group(0)!)
        .toSet();
    if (words.contains('temperatura')) {
      return _SensorVoiceSubIntent.temperature;
    }
    if (words.contains('agua') || words.contains('nivel')) {
      return _SensorVoiceSubIntent.water;
    }
    return _SensorVoiceSubIntent.general;
  }

  String _formatSpokenDouble(double v) {
    if (v == v.roundToDouble()) {
      return v.round().toString();
    }
    return v.toStringAsFixed(1);
  }

  Future<void> _executeShowSensors() async {
    _onPopToRoot?.call();
    final onIoT = _currentTabIndex == 1;
    if (!onIoT) {
      _onChangeTab?.call(1);
    }
    await _sensors.loadSensorReadings();

    switch (_sensorSubIntentFromLastPhrase()) {
      case _SensorVoiceSubIntent.temperature:
        final t = _sensors.latestRoomTemperature;
        if (t != null) {
          await speak(
            'La temperatura actual es ${_formatSpokenDouble(t)} grados',
          );
        } else {
          await speak('No hay datos de temperatura');
        }
        break;
      case _SensorVoiceSubIntent.water:
        final w = _sensors.latestTankWaterLevel;
        if (w != null) {
          await speak(
            'El nivel de agua es ${_formatSpokenDouble(w)} por ciento',
          );
        } else {
          await speak('No hay datos de agua');
        }
        break;
      case _SensorVoiceSubIntent.general:
        if (onIoT) {
          await speak('Actualizando sensores');
        } else {
          await speak('Mostrando sensores');
        }
        break;
    }
  }

  @override
  void dispose() {
    _voice.onSpeechStatus = null;
    super.dispose();
  }
}
