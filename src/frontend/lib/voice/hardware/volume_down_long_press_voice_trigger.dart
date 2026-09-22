import 'package:flutter/services.dart';

import 'hardware_voice_trigger.dart';

/// Long-press de **volumen abajo** (≥ [longPressThreshold]) → [onTrigger].
///
/// Pulsación corta no dispara (no consumimos el KeyEvent; el sistema puede
/// seguir cambiando el volumen). Solo app en primer plano.
///
/// En tests: [attachHardwareKeyboard]=false + [now] inyectable +
/// [handleVolumeDownDown]/[handleVolumeDownUp]/[tick].
class VolumeDownLongPressVoiceTrigger implements HardwareVoiceTrigger {
  VolumeDownLongPressVoiceTrigger({
    this.longPressThreshold = const Duration(milliseconds: 700),
    DateTime Function()? now,
    this.attachHardwareKeyboard = true,
  }) : _now = now ?? DateTime.now;

  final Duration longPressThreshold;
  final bool attachHardwareKeyboard;
  final DateTime Function() _now;

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
    if (event.logicalKey != LogicalKeyboardKey.audioVolumeDown) {
      return false;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      handleVolumeDownDown();
    } else if (event is KeyUpEvent) {
      handleVolumeDownUp();
    }
    return false;
  }

  /// Inicio o repetición de pulsación (evalúa umbral con el reloj actual).
  void handleVolumeDownDown() {
    _downAt ??= _now();
    tick();
  }

  void handleVolumeDownUp() {
    _downAt = null;
    _firedThisGesture = false;
  }

  /// Reevalúa si el hold actual ya superó el umbral (tests / key repeat).
  void tick() {
    if (_downAt == null || _firedThisGesture) return;
    if (_now().difference(_downAt!) >= longPressThreshold) {
      _firedThisGesture = true;
      onTrigger?.call();
    }
  }
}
