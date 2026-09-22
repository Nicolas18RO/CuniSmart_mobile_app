import '../../models/rabbit.dart';
import '../form/voice_form_field.dart';
import '../form/voice_form_field_assignment.dart';

/// Efectos que el orquestador (ViewModel) ejecuta sin contener reglas de dominio.
enum VoiceEffectType {
  popToRoot,
  changeTab,
  loadRabbits,
  loadSensorReadings,
  startSensorPolling,
  openCreateRabbitScreen,
  /// Cancela el alta por voz: limpiar bridge / salir del formulario (sin nav IoT).
  cancelCreateRabbitForm,
}

class VoiceEffect {
  const VoiceEffect(this.type, {this.tabIndex, this.formField});

  final VoiceEffectType type;
  final int? tabIndex;
  final VoiceFormField? formField;
}

/// Estado tras pedir borrado (confirmación obligatoria en [VoiceViewModel]).
class VoicePendingDelete {
  const VoicePendingDelete({
    required this.rabbitId,
    required this.rabbitUuid,
    required this.displayName,
  });

  final int rabbitId;
  final String rabbitUuid;
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
    this.shouldRestartListening = false,
    this.correctFormField,
  });

  final List<VoiceEffect> effects;
  final String? speech;
  final bool deferredSpeech;
  final VoicePendingDelete? pendingDelete;
  final List<VoiceFormFieldAssignment>? rabbitCreateFormFills;
  final VoiceUpdateByVoicePayload? updateByVoice;
  final bool shouldRestartListening;

  /// Salto local a un campo del alta (corrección); no implica API.
  final VoiceFormField? correctFormField;
}
