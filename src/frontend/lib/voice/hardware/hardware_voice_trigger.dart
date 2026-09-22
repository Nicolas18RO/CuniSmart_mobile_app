/// Contrato para activación de escucha por hardware (DESIGN post-PV D-HW).
///
/// Producción: [VolumeUpLongPressVoiceTrigger] (long-press volumen arriba).
/// Tests / degradación: [NoopHardwareVoiceTrigger].
abstract class HardwareVoiceTrigger {
  /// Se invoca cuando el PoC detecta la gestura elegida.
  void Function()? get onTrigger;
  set onTrigger(void Function()? value);

  /// Arranca/detiene la observación del hardware (no-op en [NoopHardwareVoiceTrigger]).
  void start();
  void stop();
}

/// Implementación por defecto: sin listeners de hardware.
class NoopHardwareVoiceTrigger implements HardwareVoiceTrigger {
  @override
  void Function()? onTrigger;

  @override
  void start() {}

  @override
  void stop() {}
}
