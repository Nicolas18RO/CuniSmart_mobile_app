import 'voice_form_field.dart';
import 'voice_form_field_assignment.dart';

/// Textos de confirmación y siguiente paso (solo strings; sin red).
class RabbitCreateVoiceFormGuidance {
  const RabbitCreateVoiceFormGuidance._();

  /// Ejemplo natural para TTS (día + mes escrito + año; sin ISO).
  static const naturalBirthDateExample = '15 de julio de 2026';

  /// Copy único para ayuda / error / repetir en fecha.
  static String birthDateHelpCanonical() =>
      'Indica la fecha de nacimiento. Por ejemplo: $naturalBirthDateExample. '
      'También puedes decir hoy, ayer o antier.';

  /// Instrucción a repetir para el campo activo (`repetir`).
  static String promptForField(VoiceFormField? field) {
    switch (field) {
      case VoiceFormField.name:
        return 'Di el nombre del conejo.';
      case VoiceFormField.breed:
        return 'Di la raza del conejo.';
      case VoiceFormField.sex:
        return 'Di macho o hembra.';
      case VoiceFormField.birthDate:
        return 'Di la fecha de nacimiento. ${birthDateHelpCanonical()}';
      case VoiceFormField.weight:
        return 'Indica el peso del conejo en kilogramos, por ejemplo: dos punto cinco.';
      case VoiceFormField.status:
        return 'Di el estado: activo, vendido o fallecido.';
      case VoiceFormField.notes:
        return 'Di tus notas o di sin notas.';
      case null:
        return 'Revisa el resumen y di confirmar o cancelar.';
    }
  }

  /// Ayuda contextual por campo (`ayuda`).
  static String helpForField(VoiceFormField? field) {
    switch (field) {
      case VoiceFormField.name:
        return 'Di solo el nombre, por ejemplo: Luna.';
      case VoiceFormField.breed:
        return 'Di la raza, por ejemplo: Rex o Nueva Zelanda.';
      case VoiceFormField.sex:
        return 'Di macho o hembra.';
      case VoiceFormField.birthDate:
        return birthDateHelpCanonical();
      case VoiceFormField.weight:
        return 'Di el peso en kilogramos. Por ejemplo: dos punto cinco.';
      case VoiceFormField.status:
        return 'Di activo, vendido o fallecido.';
      case VoiceFormField.notes:
        return 'Di el texto de las notas, o di sin notas.';
      case null:
        return 'Di confirmar para crear, o cancelar para abortar.';
    }
  }

  /// Respuesta cuando un comando global aparece durante el formulario.
  static String contextualBusyForField(VoiceFormField? field) {
    final focus = switch (field) {
      VoiceFormField.birthDate => 'la fecha de nacimiento',
      VoiceFormField.weight => 'el peso',
      VoiceFormField.sex => 'el sexo',
      VoiceFormField.name => 'el nombre',
      VoiceFormField.breed => 'la raza',
      VoiceFormField.status => 'el estado',
      VoiceFormField.notes => 'las notas',
      null => 'los datos del conejo',
    };
    return 'Estoy completando la información del conejo. Puedes decir $focus, '
        'repetir, pedir ayuda o cancelar.';
  }

  static String unrecognizedBirthDate() =>
      'No entendí la fecha. Puedes decir, por ejemplo: $naturalBirthDateExample, '
      'o decir hoy, ayer o antier.';

  /// Convierte `YYYY-MM-DD` a «15 de julio de 2026» para TTS (sin guiones).
  static String formatYmdForSpeech(String ymd) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(ymd.trim());
    if (m == null) return ymd;
    final y = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    final d = int.tryParse(m.group(3)!);
    if (y == null || mo == null || d == null || mo < 1 || mo > 12) return ymd;
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '$d de ${months[mo - 1]} de $y';
  }

  static String emptySttWhileForm() =>
      'No escuché nada. Repite el dato, di ayuda, o cancelar.';

  static String correctionPrompt(VoiceFormField field) {
    final label = switch (field) {
      VoiceFormField.name => 'el nombre',
      VoiceFormField.breed => 'la raza',
      VoiceFormField.sex => 'el sexo',
      VoiceFormField.birthDate => 'la fecha de nacimiento',
      VoiceFormField.weight => 'el peso',
      VoiceFormField.status => 'el estado',
      VoiceFormField.notes => 'las notas',
    };
    final ask = promptForField(field);
    return 'Vamos a corregir $label. $ask';
  }

  static String unrecognizedForField(VoiceFormField? field) {
    if (field == VoiceFormField.birthDate) return unrecognizedBirthDate();
    if (field == VoiceFormField.sex) {
      return 'No reconocí el sexo. Di macho o hembra.';
    }
    if (field == VoiceFormField.weight) {
      return 'No reconocí el peso. Di un número en kilogramos, por ejemplo: dos punto cinco.';
    }
    if (field == VoiceFormField.status) {
      return 'No reconocí el estado. Di activo, vendido o fallecido.';
    }
    if (field == VoiceFormField.notes) {
      return 'No entendí. Di tus notas o di sin notas.';
    }
    return 'No entendí. Repite o completa el campo. También puedes decir ayuda o cancelar.';
  }

  static String confirmLine(VoiceFormFieldAssignment a) {
    switch (a.field) {
      case VoiceFormField.name:
        return 'Nombre registrado: ${a.value}.';
      case VoiceFormField.breed:
        return 'Raza registrada: ${a.value}.';
      case VoiceFormField.sex:
        return 'Sexo: ${_sexEs(a.value)}.';
      case VoiceFormField.birthDate:
        return 'Fecha de nacimiento: ${formatYmdForSpeech(a.value)}.';
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
