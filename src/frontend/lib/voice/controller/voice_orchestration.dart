/// Efectos que el orquestador (ViewModel) ejecuta sin contener reglas de dominio.
enum VoiceEffectType {
  popToRoot,
  changeTab,
  loadRabbits,
  loadSensorReadings,
  startSensorPolling,
  openCreateRabbitScreen,
}

class VoiceEffect {
  const VoiceEffect(this.type, {this.tabIndex});

  final VoiceEffectType type;
  final int? tabIndex;
}

/// Plan de ejecución: efectos en orden + habla inmediata o diferida (tras efectos).
class VoiceOrchestrationResult {
  const VoiceOrchestrationResult({
    required this.effects,
    this.speech,
    this.deferredSpeech = false,
  });

  final List<VoiceEffect> effects;
  final String? speech;

  /// Si es true, el texto final sale de [VoiceController.finishDeferredSpeech]
  /// tras aplicar [effects] (p. ej. lista de conejos tras [loadRabbits]).
  final bool deferredSpeech;
}
