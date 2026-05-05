import 'voice_form_field.dart';

/// Copia de qué falta en el formulario (solo lectura para el parser de voz).
class RabbitCreateVoiceFormSnapshot {
  const RabbitCreateVoiceFormSnapshot({
    required this.routeOpen,
    required this.nameEmpty,
    required this.breedEmpty,
    required this.birthDateEmpty,
    required this.weightEmpty,
    required this.notesEmpty,
    this.activeVoiceField,
  });

  final bool routeOpen;
  final bool nameEmpty;
  final bool breedEmpty;
  final bool birthDateEmpty;
  final bool weightEmpty;
  final bool notesEmpty;

  /// Siguiente campo esperado en el flujo guiado (reintentos STT).
  final VoiceFormField? activeVoiceField;

  bool get anyRequiredEmpty =>
      nameEmpty || breedEmpty || birthDateEmpty;
}
