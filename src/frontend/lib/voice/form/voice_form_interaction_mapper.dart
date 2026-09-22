import '../form/voice_form_field.dart';
import '../form/voice_form_interaction_state.dart';
import 'rabbit_create_voice_form_snapshot.dart';

/// Mapea el snapshot / flags del bridge al estado de interacción DESIGN.
class VoiceFormInteractionMapper {
  const VoiceFormInteractionMapper._();

  static VoiceFormInteractionState fromSnapshot(
    RabbitCreateVoiceFormSnapshot snap, {
    bool awaitingFinalConfirmation = false,
    bool saving = false,
    bool cancelled = false,
    bool success = false,
    bool error = false,
  }) {
    if (cancelled) return VoiceFormInteractionState.cancelled;
    if (success) return VoiceFormInteractionState.success;
    if (error) return VoiceFormInteractionState.error;
    if (saving) return VoiceFormInteractionState.saving;
    if (!snap.routeOpen) return VoiceFormInteractionState.idle;
    if (awaitingFinalConfirmation) {
      return VoiceFormInteractionState.confirming;
    }
    return switch (snap.activeVoiceField) {
      VoiceFormField.name => VoiceFormInteractionState.askingName,
      VoiceFormField.breed => VoiceFormInteractionState.askingBreed,
      VoiceFormField.sex => VoiceFormInteractionState.askingSex,
      VoiceFormField.birthDate => VoiceFormInteractionState.askingBirthDate,
      VoiceFormField.weight => VoiceFormInteractionState.askingWeight,
      VoiceFormField.status => VoiceFormInteractionState.askingStatus,
      VoiceFormField.notes => VoiceFormInteractionState.askingNotes,
      null => VoiceFormInteractionState.confirming,
    };
  }
}
