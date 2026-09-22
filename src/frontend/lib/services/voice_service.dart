import 'dart:async';

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
/// [startListening] is only for explicit user-driven sessions (e.g. mic tap)
/// or recovery after TTS when the ViewModel requests it.
/// It does not schedule listening from [onResult] / status by itself.
class VoiceService {
  VoiceService()
      : _speech = SpeechToText(),
        _tts = FlutterTts();

  final SpeechToText _speech;
  final FlutterTts _tts;

  bool _speechInitialized = false;
  bool _ttsCompletionConfigured = false;
  List<String> _sttLocaleIds = const [];
  bool _isSpeaking = false;
  Completer<void>? _speakDone;

  /// Last words from the most recent **final** recognition in the current/last session.
  String? lastRecognizedWords;

  void Function(String status)? onSpeechStatus;
  void Function(SpeechRecognitionError error)? onSpeechError;

  bool get isListening => _speech.isListening;

  /// True while TTS is producing audio (blocks [startListening]).
  bool get isSpeaking => _isSpeaking;

  Future<void> _configureTtsCompletion() async {
    if (_ttsCompletionConfigured) return;
    _ttsCompletionConfigured = true;
    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('VoiceService: awaitSpeakCompletion failed: $e');
    }
    try {
      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        final c = _speakDone;
        if (c != null && !c.isCompleted) {
          c.complete();
        }
      });
    } catch (e) {
      debugPrint('VoiceService: setCompletionHandler failed: $e');
    }
  }

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
      await _configureTtsCompletion();
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

  /// Starts one listening session. Blocked while [isSpeaking].
  Future<void> startListening({
    void Function(SpeechRecognitionResult result)? onRecognitionResult,
    Duration? pauseFor,
    Duration? listenFor,
  }) async {
    if (_isSpeaking) {
      debugPrint('VoiceService: startListening blocked (TTS speaking)');
      return;
    }
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

  /// Speaks [text] and awaits TTS completion when the platform supports it.
  Future<void> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;

    await _configureTtsCompletion();

    _isSpeaking = true;
    final done = Completer<void>();
    _speakDone = done;

    try {
      await _tts.speak(t);
      // Prefer completion handler; fall back to timeout based on text length.
      await done.future.timeout(
        Duration(milliseconds: (t.length * 80).clamp(800, 20000)),
        onTimeout: () {},
      );
    } catch (e, st) {
      debugPrint('VoiceService: speak failed: $e\n$st');
    } finally {
      _isSpeaking = false;
      if (!done.isCompleted) {
        done.complete();
      }
      _speakDone = null;
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _isSpeaking = false;
    final c = _speakDone;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
    _speakDone = null;
  }

  Future<void> dispose() async {
    await stopListening();
    await stopSpeaking();
  }
}
