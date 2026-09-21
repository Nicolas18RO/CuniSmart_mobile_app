import 'rabbit_create_voice_form_snapshot.dart';
import 'voice_form_field.dart';
import 'voice_form_field_assignment.dart';

/// Extrae asignaciones de campos desde frases de voz (orden fijo en ráfaga).
class RabbitCreateVoiceFormParser {
  const RabbitCreateVoiceFormParser();

  static final _noise = RegExp(r'[^\p{L}\p{N}\s.,/-]+', unicode: true);

  /// Frases que no son datos del formulario (evita asignar "la siguiente pregunta" a la raza).
  static bool isNonFormChatter(String phrase) {
    final n = _norm(phrase);
    if (n.isEmpty) return true;
    return RegExp(
      r'\b(cuál|cual|qué|pregunta|preguntas|siguiente|ayuda|instrucciones|'
      r'no\s+sé|no\s+se|no\s+entiendo|explica|explicar)\b',
      caseSensitive: false,
    ).hasMatch(n);
  }

  static String _norm(String raw) {
    var s = raw.toLowerCase().trim();
    s = s.replaceAll(_noise, ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.trim();
  }

  /// Frase completa tras «crear|registrar|agregar … conejo».
  static List<VoiceFormFieldAssignment> parseBurst(String remainder) {
    var s = remainder.trim();
    if (s.isEmpty) return const [];

    var n = _norm(s);
    String? notesVal;
    String? statusVal;
    String? weightVal;
    String? birthVal;
    String? sexVal;

    // notas …
    final notesRe = RegExp(r'\bnotas\s+(.+)$', caseSensitive: false);
    final notesM = notesRe.firstMatch(n);
    if (notesM != null) {
      notesVal = notesM.group(1)!.trim();
      n = n.substring(0, notesM.start).trim();
    }

    // estado al final
    final stRe = RegExp(
      r'\b(activo|activa|vendido|vendida|fallecido|fallecida)\s*$',
      caseSensitive: false,
    );
    final stM = stRe.firstMatch(n);
    if (stM != null) {
      statusVal = _statusApi(stM.group(1)!);
      n = n.substring(0, stM.start).trim();
    }

    // peso al final
    if (RegExp(r'\bsin\s+peso\s*$').hasMatch(n)) {
      weightVal = '';
      n = n.replaceFirst(RegExp(r'\bsin\s+peso\s*$'), '').trim();
    } else {
      final wRe = RegExp(
        r'\b(\d+[.,]\d+|\d+)\s*(?:kg|kilos|kilogramos)?\s*$',
        caseSensitive: false,
      );
      final wm = wRe.firstMatch(n);
      if (wm != null) {
        weightVal = wm.group(1)!.replaceAll(',', '.');
        n = n.substring(0, wm.start).trim();
      }
    }

    // fecha al final
    final ymdEnd = RegExp(
      r'\b(\d{4})[\s/-]+(\d{1,2})[\s/-]+(\d{1,2})\s*$',
    );
    var dm = ymdEnd.firstMatch(n);
    if (dm != null) {
      birthVal = _fmtYmd(
        int.tryParse(dm.group(1)!),
        int.tryParse(dm.group(2)!),
        int.tryParse(dm.group(3)!),
      );
      if (birthVal != null) {
        n = n.substring(0, dm.start).trim();
      }
    }
    if (birthVal == null) {
      final dmyEnd = RegExp(r'\b(\d{1,2})[\s/-]+(\d{1,2})[\s/-]+(\d{4})\s*$');
      final dmyM = dmyEnd.firstMatch(n);
      if (dmyM != null) {
        birthVal = _fmtYmd(
          int.tryParse(dmyM.group(3)!),
          int.tryParse(dmyM.group(2)!),
          int.tryParse(dmyM.group(1)!),
        );
        if (birthVal != null) {
          n = n.substring(0, dmyM.start).trim();
        }
      }
    }
    if (birthVal == null) {
      final dayMonthYear = RegExp(
        r'\b(\d{1,2})\s+([a-záéíóúñ]+)\s+(\d{4})\s*$',
        unicode: true,
      ).firstMatch(n);
      if (dayMonthYear != null) {
        final mon = _monthFromSpanish(dayMonthYear.group(2)!);
        birthVal = _fmtYmd(
          int.tryParse(dayMonthYear.group(3)!),
          mon,
          int.tryParse(dayMonthYear.group(1)!),
        );
        if (birthVal != null) {
          n = n.substring(0, dayMonthYear.start).trim();
        }
      }
    }
    if (birthVal == null) {
      final monthDayYear = RegExp(
        r'\b([a-záéíóúñ]+)\s+(\d{1,2})\s+(\d{4})\s*$',
        unicode: true,
      ).firstMatch(n);
      if (monthDayYear != null) {
        final mon = _monthFromSpanish(monthDayYear.group(1)!);
        birthVal = _fmtYmd(
          int.tryParse(monthDayYear.group(3)!),
          mon,
          int.tryParse(monthDayYear.group(2)!),
        );
        if (birthVal != null) {
          n = n.substring(0, monthDayYear.start).trim();
        }
      }
    }
    if (birthVal == null) {
      final naturalEnd = RegExp(
        r'\b(\d{1,2})\s+de\s+([a-záéíóúñ]+)\s+de\s+(\d{4})\s*$',
        unicode: true,
      ).firstMatch(n);
      if (naturalEnd != null) {
        final day = int.tryParse(naturalEnd.group(1)!);
        final mon = _monthFromSpanish(naturalEnd.group(2)!);
        final year = int.tryParse(naturalEnd.group(3)!);
        birthVal = _fmtYmd(year, mon, day);
        if (birthVal != null) {
          n = n.substring(0, naturalEnd.start).trim();
        }
      }
    }

    // sexo
    final sexRe = RegExp(r'\b(hembra|macho)\s*$', caseSensitive: false);
    final sxM = sexRe.firstMatch(n);
    if (sxM != null) {
      sexVal = sxM.group(1)!.toLowerCase() == 'hembra' ? 'female' : 'male';
      n = n.substring(0, sxM.start).trim();
    }

    final out = <VoiceFormFieldAssignment>[];
    if (n.isNotEmpty) {
      final parts = n.split(RegExp(r'\s+'));
      final name = parts.first;
      final breed = parts.sublist(1).join(' ');
      out.add(VoiceFormFieldAssignment(VoiceFormField.name, _titleCaseWords(name)));
      if (breed.trim().isNotEmpty) {
        out.add(VoiceFormFieldAssignment(VoiceFormField.breed, _titleCaseWords(breed)));
      }
    }
    if (sexVal != null) {
      out.add(VoiceFormFieldAssignment(VoiceFormField.sex, sexVal));
    }
    if (birthVal != null) {
      out.add(VoiceFormFieldAssignment(VoiceFormField.birthDate, birthVal));
    }
    if (weightVal != null) {
      out.add(VoiceFormFieldAssignment(VoiceFormField.weight, weightVal));
    }
    if (statusVal != null) {
      out.add(VoiceFormFieldAssignment(VoiceFormField.status, statusVal));
    }
    if (notesVal != null && notesVal.isNotEmpty) {
      out.add(VoiceFormFieldAssignment(VoiceFormField.notes, notesVal));
    }
    return out;
  }

  /// Una frase corta mientras el formulario está abierto (rellena el siguiente hueco).
  static List<VoiceFormFieldAssignment> parseContinuation(
    String phrase,
    RabbitCreateVoiceFormSnapshot snap,
  ) {
    final t = phrase.trim();
    if (t.isEmpty) return const [];

    final lower = _norm(t);

    if (isNonFormChatter(t)) {
      return const [];
    }

    final focused = snap.activeVoiceField;
    if (focused != null) {
      final only = _parseContinuationFocused(t, lower, focused);
      if (only.isNotEmpty) return only;
      return const [];
    }

    if (snap.nameEmpty) {
      return [VoiceFormFieldAssignment(VoiceFormField.name, _titleCaseWords(t))];
    }

    if (snap.breedEmpty) {
      return [VoiceFormFieldAssignment(VoiceFormField.breed, _titleCaseWords(t))];
    }

    if (RegExp(r'\b(hembra|macho)\b').hasMatch(lower)) {
      final sx = lower.contains('hembra') ? 'female' : 'male';
      return [VoiceFormFieldAssignment(VoiceFormField.sex, sx)];
    }

    final iso = _parseBirthDateFlexible(lower);
    if (iso != null && snap.birthDateEmpty) {
      return [VoiceFormFieldAssignment(VoiceFormField.birthDate, iso)];
    }

    if (RegExp(r'^sin\s+peso$').hasMatch(lower)) {
      return const [VoiceFormFieldAssignment(VoiceFormField.weight, '')];
    }
    final wOnly = RegExp(r'^(\d+[.,]\d+|\d+)\s*(?:kg|kilos|kilogramos)?$')
        .firstMatch(lower);
    if (wOnly != null && snap.weightEmpty) {
      return [
        VoiceFormFieldAssignment(
          VoiceFormField.weight,
          wOnly.group(1)!.replaceAll(',', '.'),
        ),
      ];
    }

    if (RegExp(r'\b(activo|activa|vendido|vendida|fallecido|fallecida)\b')
        .hasMatch(lower)) {
      return [
        VoiceFormFieldAssignment(VoiceFormField.status, _statusFromPhrase(lower)),
      ];
    }

    if (lower.startsWith('notas ')) {
      return [
        VoiceFormFieldAssignment(
          VoiceFormField.notes,
          t.substring(t.toLowerCase().indexOf('notas ') + 6).trim(),
        ),
      ];
    }

    if (RegExp(r'^sin\s+notas$').hasMatch(lower)) {
      return const [VoiceFormFieldAssignment(VoiceFormField.notes, '')];
    }

    return const [];
  }

  /// Interpretación acotada al campo activo (reintentos STT sin saltar a otro campo).
  static List<VoiceFormFieldAssignment> _parseContinuationFocused(
    String originalTrimmed,
    String lower,
    VoiceFormField field,
  ) {
    switch (field) {
      case VoiceFormField.name:
        return [
          VoiceFormFieldAssignment(
            VoiceFormField.name,
            _titleCaseWords(originalTrimmed),
          ),
        ];
      case VoiceFormField.breed:
        return [
          VoiceFormFieldAssignment(
            VoiceFormField.breed,
            _titleCaseWords(originalTrimmed),
          ),
        ];
      case VoiceFormField.sex:
        if (RegExp(r'\b(hembra|macho)\b').hasMatch(lower)) {
          final sx = lower.contains('hembra') ? 'female' : 'male';
          return [VoiceFormFieldAssignment(VoiceFormField.sex, sx)];
        }
        return const [];
      case VoiceFormField.birthDate:
        final iso = _parseBirthDateFlexible(lower);
        if (iso != null) {
          return [VoiceFormFieldAssignment(VoiceFormField.birthDate, iso)];
        }
        return const [];
      case VoiceFormField.weight:
        if (RegExp(r'^sin\s+peso$').hasMatch(lower)) {
          return const [VoiceFormFieldAssignment(VoiceFormField.weight, '')];
        }
        final wOnly = RegExp(
              r'^(\d+[.,]\d+|\d+)\s*(?:kg|kilos|kilogramos)?$',
            )
            .firstMatch(lower);
        if (wOnly != null) {
          return [
            VoiceFormFieldAssignment(
              VoiceFormField.weight,
              wOnly.group(1)!.replaceAll(',', '.'),
            ),
          ];
        }
        final loose = RegExp(r'^(\d+[.,]\d+|\d+)$').firstMatch(lower);
        if (loose != null) {
          return [
            VoiceFormFieldAssignment(
              VoiceFormField.weight,
              loose.group(1)!.replaceAll(',', '.'),
            ),
          ];
        }
        return const [];
      case VoiceFormField.status:
        if (RegExp(r'\b(activo|activa|vendido|vendida|fallecido|fallecida)\b')
            .hasMatch(lower)) {
          return [
            VoiceFormFieldAssignment(
              VoiceFormField.status,
              _statusFromPhrase(lower),
            ),
          ];
        }
        return const [];
      case VoiceFormField.notes:
        if (lower.startsWith('notas ')) {
          return [
            VoiceFormFieldAssignment(
              VoiceFormField.notes,
              originalTrimmed
                  .substring(
                    originalTrimmed.toLowerCase().indexOf('notas ') + 6,
                  )
                  .trim(),
            ),
          ];
        }
        if (RegExp(r'^sin\s+notas$').hasMatch(lower)) {
          return const [VoiceFormFieldAssignment(VoiceFormField.notes, '')];
        }
        return [
          VoiceFormFieldAssignment(VoiceFormField.notes, originalTrimmed),
        ];
    }
  }

  static String _titleCaseWords(String s) {
    if (s.isEmpty) return s;
    return s
        .split(RegExp(r'\s+'))
        .map((w) {
          if (w.isEmpty) return w;
          return w[0].toUpperCase() + w.substring(1).toLowerCase();
        })
        .join(' ');
  }

  static String _statusApi(String token) {
    final x = token.toLowerCase();
    if (x.startsWith('vend')) return 'sold';
    if (x.startsWith('fall')) return 'deceased';
    return 'active';
  }

  static String _statusFromPhrase(String lower) {
    if (lower.contains('vendido') || lower.contains('vendida')) {
      return 'sold';
    }
    if (lower.contains('fallecido') || lower.contains('fallecida')) {
      return 'deceased';
    }
    return 'active';
  }

  static String? _fmtYmd(int? y, int? m, int? d) {
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    if (y < 1900 || y > 2100) return null;
    final mm = m.toString().padLeft(2, '0');
    final dd = d.toString().padLeft(2, '0');
    return '$y-$mm-$dd';
  }

  static int? _monthFromSpanish(String token) {
    const map = {
      'enero': 1,
      'febrero': 2,
      'marzo': 3,
      'abril': 4,
      'mayo': 5,
      'junio': 6,
      'julio': 7,
      'agosto': 8,
      'septiembre': 9,
      'setiembre': 9,
      'octubre': 10,
      'noviembre': 11,
      'diciembre': 12,
    };
    return map[token];
  }

  static String? _parseBirthDateFlexible(String n) {
    if (n.isEmpty) return null;
    final natural = RegExp(
      r'^(\d{1,2})\s+de\s+([a-záéíóúñ]+)\s+de\s+(\d{4})$',
      unicode: true,
    ).firstMatch(n);
    if (natural != null) {
      final day = int.tryParse(natural.group(1)!);
      final mon = _monthFromSpanish(natural.group(2)!);
      return _fmtYmd(int.tryParse(natural.group(3)!), mon, day);
    }
    final ymd = RegExp(
      r'^(\d{4})[\s/-]+(\d{1,2})[\s/-]+(\d{1,2})$',
    ).firstMatch(n);
    if (ymd != null) {
      return _fmtYmd(
        int.tryParse(ymd.group(1)!),
        int.tryParse(ymd.group(2)!),
        int.tryParse(ymd.group(3)!),
      );
    }
    final dmy = RegExp(
      r'^(\d{1,2})[\s/-]+(\d{1,2})[\s/-]+(\d{4})$',
    ).firstMatch(n);
    if (dmy != null) {
      return _fmtYmd(
        int.tryParse(dmy.group(3)!),
        int.tryParse(dmy.group(2)!),
        int.tryParse(dmy.group(1)!),
      );
    }
    final dayMonthYear = RegExp(
      r'^(\d{1,2})\s+([a-záéíóúñ]+)\s+(\d{4})$',
      unicode: true,
    ).firstMatch(n);
    if (dayMonthYear != null) {
      final mon = _monthFromSpanish(dayMonthYear.group(2)!);
      return _fmtYmd(
        int.tryParse(dayMonthYear.group(3)!),
        mon,
        int.tryParse(dayMonthYear.group(1)!),
      );
    }
    final monthDayYear = RegExp(
      r'^([a-záéíóúñ]+)\s+(\d{1,2})\s+(\d{4})$',
      unicode: true,
    ).firstMatch(n);
    if (monthDayYear != null) {
      final mon = _monthFromSpanish(monthDayYear.group(1)!);
      return _fmtYmd(
        int.tryParse(monthDayYear.group(3)!),
        mon,
        int.tryParse(monthDayYear.group(2)!),
      );
    }
    return null;
  }
}
