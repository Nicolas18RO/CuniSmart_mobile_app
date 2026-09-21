import 'voice_form_field.dart';

/// Una asignación de voz → campo (valores ya normalizados para la UI/API).
class VoiceFormFieldAssignment {
  const VoiceFormFieldAssignment(this.field, this.value);

  final VoiceFormField field;

  /// Texto para inputs; sexo `male`/`female`; estado `active`/`sold`/`deceased`;
  /// peso cadena vacía = sin peso.
  final String value;
}
