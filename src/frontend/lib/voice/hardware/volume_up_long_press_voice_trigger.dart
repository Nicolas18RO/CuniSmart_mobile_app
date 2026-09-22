import 'package:flutter/services.dart';

import 'hardware_voice_trigger.dart';

/// Long-press de **volumen arriba** (≥ [longPressThreshold]) → [onTrigger].
///
/// Pulsación corta no dispara. FAB permanece como fallback.
class VolumeUpLongPressVoiceTrigger implements HardwareVoiceTrigger {
  VolumeUpLongPressVoiceTrigger({
    this.longPressThreshold = const Duration(milliseconds: 700),
    DateTime Function()? now,
    this.attachHardwareKeyboard = true,
  }) : _now = now ?? DateTime.now;

  final Duration longPressThreshold;
  final bool attachHardwareKeyboard;
  final DateTime Function() _now;

  /// Tecla física usada (Volume Up).
  LogicalKeyboardKey get volumeKey => LogicalKeyboardKey.audioVolumeUp;

  DateTime? _downAt;
  bool _firedThisGesture = false;
  bool _listening = false;
  bool _handlerAttached = false;

  @override
  void Function()? onTrigger;

  bool get isListening => _listening;

  @override
  void start() {
    if (_listening) return;
    _listening = true;
    if (attachHardwareKeyboard && !_handlerAttached) {
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
      _handlerAttached = true;
    }
  }

  @override
  void stop() {
    if (!_listening) return;
    _listening = false;
    if (_handlerAttached) {
      HardwareKeyboard.instance.removeHandler(_onKeyEvent);
      _handlerAttached = false;
    }
    _downAt = null;
    _firedThisGesture = false;
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event.logicalKey != volumeKey) {
      return false;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      handleVolumeUpDown();
    } else if (event is KeyUpEvent) {
      handleVolumeUpUp();
    }
    return false;
  }

  void handleVolumeUpDown() {
    _downAt ??= _now();
    tick();
  }

  void handleVolumeUpUp() {
    _downAt = null;
    _firedThisGesture = false;
  }

  void tick() {
    if (_downAt == null || _firedThisGesture) return;
    if (_now().difference(_downAt!) >= longPressThreshold) {
      _firedThisGesture = true;
      onTrigger?.call();
    }
  }
}
