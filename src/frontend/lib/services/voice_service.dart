import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Preferred order for Spanish speech recognition (device must expose one).
const List<String> _kPreferredSttSpanishLocaleIds = [
  'es_ES',
  'es_CO',
  'es_MX',
  'es_US',
];

/// Thin wrapper around device STT + TTS. No UI or ViewModel coupling.
///
/// [startListening] is only for explicit user-driven sessions (e.g. mic tap).
/// It does not schedule or restart listening from [onResult] / status / errors.
class VoiceService {
  VoiceService()
      : _speech = SpeechToText(),
        _tts = FlutterTts();

  final SpeechToText _speech;
  final FlutterTts _tts;

  bool _speechInitialized = false;
  List<String> _sttLocaleIds = const [];

  /// Last words from the most recent **final** recognition in the current/last session.
  String? lastRecognizedWords;

  void Function(String status)? onSpeechStatus;
  void Function(SpeechRecognitionError error)? onSpeechError;

  bool get isListening => _speech.isListening;

  /// Initializes speech recognition (mic permission may be requested).
  Future<bool> ensureInitialized() async {
    if (_speechInitialized) {
      return _speech.isAvailable;
    }
    _speechInitialized = await _speech.initialize(
      debugLogging: false,
      onError: (e) {
        onSpeechError?.call(e);
      },
      onStatus: (status) {
        onSpeechStatus?.call(status);
      },
    );
    if (_speechInitialized) {
      try {
        final locales = await _speech.locales();
        _sttLocaleIds = locales.map((e) => e.localeId).toList();
      } catch (e, st) {
        debugPrint('VoiceService: locales() failed: $e\n$st');
      }
      try {
        await _tts.setLanguage('es-ES');
      } catch (e) {
        debugPrint('VoiceService: TTS setLanguage(es-ES) failed: $e');
      }
    }
    return _speechInitialized && _speech.isAvailable;
  }

  String _localeIdForSpanishListen() {
    for (final id in _kPreferredSttSpanishLocaleIds) {
      if (_sttLocaleIds.contains(id)) return id;
    }
    for (final id in _sttLocaleIds) {
      if (id.startsWith('es')) return id;
    }
    return 'es_ES';
  }

  static const Duration _defaultListenFor = Duration(seconds: 15);
  static const Duration _defaultPauseFor = Duration(seconds: 5);

  /// Starts one listening session. Does not auto-restart when it ends.
  Future<void> startListening({
    void Function(SpeechRecognitionResult result)? onRecognitionResult,
    Duration? pauseFor,
    Duration? listenFor,
  }) async {
    if (_speech.isListening) {
      return;
    }
    final ok = await ensureInitialized();
    if (!ok) {
      debugPrint('VoiceService: start listening failed (not available)');
      return;
    }

    final mic = await _speech.hasPermission;
    if (!mic) {
      debugPrint('VoiceService: start listening aborted (no mic permission)');
      return;
    }

    final localeId = _localeIdForSpanishListen();
    debugPrint('VoiceService: start listening');

    lastRecognizedWords = null;

    final effectiveListenFor = listenFor ?? _defaultListenFor;
    final effectivePauseFor = pauseFor ?? _defaultPauseFor;

    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          if (!result.finalResult) {
            return;
          }
          lastRecognizedWords = result.recognizedWords;
          onRecognitionResult?.call(result);
          debugPrint(
            'VoiceService: final result "${result.recognizedWords}"',
          );
        },
        pauseFor: effectivePauseFor,
        listenFor: effectiveListenFor,
        localeId: localeId,
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          cancelOnError: true,
          partialResults: true,
        ),
      );
    } catch (e, st) {
      debugPrint('VoiceService: listen() threw: $e\n$st');
    }
  }

  Future<void> stopListening() async {
    if (!_speech.isListening) {
      return;
    }
    await _speech.stop();
  }

  Future<void> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await _tts.speak(t);
  }

  Future<void> dispose() async {
    await stopListening();
    await _tts.stop();
  }
}
