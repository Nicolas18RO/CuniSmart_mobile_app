import 'voice_form_field.dart';
import 'voice_form_field_assignment.dart';

/// Textos de confirmación y siguiente paso (solo strings; sin red).
class RabbitCreateVoiceFormGuidance {
  const RabbitCreateVoiceFormGuidance._();

  static String confirmLine(VoiceFormFieldAssignment a) {
    switch (a.field) {
      case VoiceFormField.name:
        return 'Nombre registrado: ${a.value}.';
      case VoiceFormField.breed:
        return 'Raza registrada: ${a.value}.';
      case VoiceFormField.sex:
        return 'Sexo: ${_sexEs(a.value)}.';
      case VoiceFormField.birthDate:
        return 'Fecha de nacimiento: ${a.value}.';
      case VoiceFormField.weight:
        return a.value.isEmpty
            ? 'Sin peso registrado.'
            : 'Peso: ${a.value} kilos.';
      case VoiceFormField.status:
        return 'Estado: ${_statusEs(a.value)}.';
      case VoiceFormField.notes:
        return a.value.isEmpty ? 'Sin notas.' : 'Notas guardadas.';
    }
  }

  static String burstClosingLine() =>
      'Revisa el formulario y pulsa Crear para guardar el conejo.';

  static String _sexEs(String api) => api == 'female' ? 'hembra' : 'macho';

  static String _statusEs(String api) {
    switch (api) {
      case 'sold':
        return 'vendido';
      case 'deceased':
        return 'fallecido';
      default:
        return 'activo';
    }
  }

  /// TTS de una sola ráfaga: confirma cada campo y cierra.
  static String forBurst(List<VoiceFormFieldAssignment> applied) {
    if (applied.isEmpty) return '';
    final parts = applied.map(confirmLine).toList();
    parts.add(burstClosingLine());
    return parts.join(' ');
  }
}
