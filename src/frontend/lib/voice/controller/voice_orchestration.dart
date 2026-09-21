import '../../models/rabbit.dart';
import '../form/voice_form_field_assignment.dart';

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

/// Estado tras pedir borrado (confirmación obligatoria en [VoiceViewModel]).
class VoicePendingDelete {
  const VoicePendingDelete({
    required this.rabbitId,
    required this.displayName,
  });

  final int rabbitId;
  final String displayName;
}

/// Payload para PUT update (solo campos conocidos + peso nuevo).
class VoiceUpdateByVoicePayload {
  const VoiceUpdateByVoicePayload({
    required this.snapshot,
    required this.newWeight,
  });

  final Rabbit snapshot;
  final double newWeight;
}

/// Plan de ejecución: efectos en orden + habla inmediata o diferida (tras efectos).
class VoiceOrchestrationResult {
  const VoiceOrchestrationResult({
    required this.effects,
    this.speech,
    this.deferredSpeech = false,
    this.pendingDelete,
    this.rabbitCreateFormFills,
    this.updateByVoice,
  });

  final List<VoiceEffect> effects;
  final String? speech;

  /// Si es true, el texto final sale de [VoiceController.finishDeferredSpeech]
  /// tras aplicar [effects] (p. ej. lista de conejos tras [loadRabbits]).
  final bool deferredSpeech;

  final VoicePendingDelete? pendingDelete;
  final List<VoiceFormFieldAssignment>? rabbitCreateFormFills;
  final VoiceUpdateByVoicePayload? updateByVoice;
}
