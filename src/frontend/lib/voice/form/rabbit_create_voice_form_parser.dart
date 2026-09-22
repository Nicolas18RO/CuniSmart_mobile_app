import 'rabbit_create_voice_form_snapshot.dart';
import 'voice_form_field.dart';
import 'voice_form_field_assignment.dart';

/// Extrae asignaciones de campos desde frases de voz (orden fijo en ráfaga).
class RabbitCreateVoiceFormParser {
  const RabbitCreateVoiceFormParser();

  /// Solo tests: fija “hoy” local. Producción usa [DateTime.now].
  static DateTime? debugTodayOverride;

  static DateTime _todayLocal() {
    final n = debugTodayOverride ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static final _noise = RegExp(r'[^\p{L}\p{N}\s.,/-]+', unicode: true);

  /// Frases que no son datos del formulario (evita asignar "la siguiente pregunta" a la raza).
  static bool isNonFormChatter(String phrase) {
    final n = _norm(phrase);
    if (n.isEmpty) return true;
    return RegExp(
      r'\b(cuál|cual|qué|pregunta|preguntas|siguiente|instrucciones|'
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
    final wFlex = _parseWeightFlexible(lower);
    if (wFlex != null && snap.weightEmpty) {
      return [
        VoiceFormFieldAssignment(VoiceFormField.weight, wFlex),
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
        if (RegExp(r'\b(gramos?|\bg\b)\b').hasMatch(lower) &&
            !RegExp(r'\b(kg|kilos|kilogramos)\b').hasMatch(lower)) {
          return const [];
        }
        final w = _parseWeightFlexible(lower);
        if (w != null) {
          return [VoiceFormFieldAssignment(VoiceFormField.weight, w)];
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

  static String? _fmtYmdFromDate(DateTime d) =>
      _fmtYmd(d.year, d.month, d.day);

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
    return map[_stripAccents(token)];
  }

  static String _stripAccents(String s) {
    const from = 'áéíóúüñ';
    const to = 'aeiouun';
    final b = StringBuffer();
    for (final c in s.split('')) {
      final i = from.indexOf(c);
      b.write(i >= 0 ? to[i] : c);
    }
    return b.toString();
  }

  /// Normaliza para fecha: minúsculas ya aplicadas, quita tildes, `del`→`de`.
  static String _prepareDatePhrase(String n) {
    var s = _stripAccents(n.trim());
    s = s.replaceAll(RegExp(r'\bdel\b'), 'de');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static int? _parseCardinal0to99(String raw) {
    final t = _stripAccents(raw.trim());
    final asInt = int.tryParse(t);
    if (asInt != null && asInt >= 0 && asInt <= 99) return asInt;

    const map = <String, int>{
      'cero': 0,
      'uno': 1,
      'una': 1,
      'dos': 2,
      'tres': 3,
      'cuatro': 4,
      'cinco': 5,
      'seis': 6,
      'siete': 7,
      'ocho': 8,
      'nueve': 9,
      'diez': 10,
      'once': 11,
      'doce': 12,
      'trece': 13,
      'catorce': 14,
      'quince': 15,
      'dieciseis': 16,
      'diecisiete': 17,
      'dieciocho': 18,
      'diecinueve': 19,
      'veinte': 20,
      'veintiuno': 21,
      'veintiuna': 21,
      'veintidos': 22,
      'veintitres': 23,
      'veinticuatro': 24,
      'veinticinco': 25,
      'veintiseis': 26,
      'veintisiete': 27,
      'veintiocho': 28,
      'veintinueve': 29,
      'treinta': 30,
      'treinta y uno': 31,
      'treinta y una': 31,
    };
    // Longest keys first.
    final keys = map.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final k in keys) {
      if (t == k) return map[k];
    }
    // "veinti dos" style rare STT splits
    final veinti = RegExp(r'^veinti\s*(uno|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve)$')
        .firstMatch(t);
    if (veinti != null) {
      final u = _parseCardinal0to99(veinti.group(1)!);
      if (u != null) return 20 + u;
    }
    final treintaY = RegExp(r'^treinta\s+y\s+(uno|una)$').firstMatch(t);
    if (treintaY != null) return 31;
    return null;
  }

  static int? _parseDayToken(String raw) {
    final n = _parseCardinal0to99(raw);
    if (n == null || n < 1 || n > 31) return null;
    return n;
  }

  /// Extrae kg como string numérico (`15`, `2.5`). `null` = no reconocido.
  static String? _parseWeightFlexible(String lower) {
    var s = _stripAccents(lower.trim());
    s = s.replaceFirst(RegExp(r'^(el\s+)?peso\s+(es\s+)?'), '');
    s = s.replaceFirst(RegExp(r'\s*(kg|kilos|kilogramos)\s*$'), '').trim();
    if (s.isEmpty) return null;

    final digit = RegExp(r'^(\d+[.,]\d+|\d+)$').firstMatch(s);
    if (digit != null) {
      return digit.group(1)!.replaceAll(',', '.');
    }

    final decimal = RegExp(r'^(.+?)\s+(punto|coma)\s+(.+)$').firstMatch(s);
    if (decimal != null) {
      final whole = _parseCardinal0to99(decimal.group(1)!);
      final frac = _parseCardinal0to99(decimal.group(3)!);
      if (whole != null && frac != null && frac >= 0) {
        return '$whole.$frac';
      }
    }

    final spoken = _parseCardinal0to99(s);
    if (spoken != null) return spoken.toString();
    return null;
  }

  static int? _parseYearToken(String raw) {
    final t = _stripAccents(raw.trim());
    final asInt = int.tryParse(t);
    if (asInt != null) return asInt;
    if (t == 'dos mil') return 2000;
    if (t.startsWith('dos mil ')) {
      final rest = t.substring('dos mil '.length).trim().replaceFirst(
            RegExp(r'^y\s+'),
            '',
          );
      final n = _parseCardinal0to99(rest);
      if (n != null && n >= 0 && n <= 99) return 2000 + n;
    }
    return null;
  }

  static String? _parseBirthDateFlexible(String n) {
    if (n.isEmpty) return null;
    final s = _prepareDatePhrase(n);

    // Relativas (solo fecha local, sin hora).
    if (s == 'hoy') {
      return _fmtYmdFromDate(_todayLocal());
    }
    if (s == 'ayer') {
      return _fmtYmdFromDate(_todayLocal().subtract(const Duration(days: 1)));
    }
    if (s == 'antier' || s == 'antes de ayer' || s == 'anteayer') {
      return _fmtYmdFromDate(_todayLocal().subtract(const Duration(days: 2)));
    }

    // "25 de septiembre de 2026" | "veinticinco de septiembre de dos mil veintiseis"
    final natural = RegExp(
      r'^(.+?)\s+de\s+([a-zñ]+)\s+de\s+(.+)$',
    ).firstMatch(s);
    if (natural != null) {
      final day = _parseDayToken(natural.group(1)!);
      final mon = _monthFromSpanish(natural.group(2)!);
      final year = _parseYearToken(natural.group(3)!);
      final iso = _fmtYmd(year, mon, day);
      if (iso != null) return iso;
    }

    final ymd = RegExp(
      r'^(\d{4})[\s/-]+(\d{1,2})[\s/-]+(\d{1,2})$',
    ).firstMatch(s);
    if (ymd != null) {
      return _fmtYmd(
        int.tryParse(ymd.group(1)!),
        int.tryParse(ymd.group(2)!),
        int.tryParse(ymd.group(3)!),
      );
    }
    final dmy = RegExp(
      r'^(\d{1,2})[\s/-]+(\d{1,2})[\s/-]+(\d{4})$',
    ).firstMatch(s);
    if (dmy != null) {
      return _fmtYmd(
        int.tryParse(dmy.group(3)!),
        int.tryParse(dmy.group(2)!),
        int.tryParse(dmy.group(1)!),
      );
    }
    final dayMonthYear = RegExp(
      r'^(.+?)\s+([a-zñ]+)\s+(.+)$',
    ).firstMatch(s);
    if (dayMonthYear != null &&
        _monthFromSpanish(dayMonthYear.group(2)!) != null) {
      final day = _parseDayToken(dayMonthYear.group(1)!);
      final mon = _monthFromSpanish(dayMonthYear.group(2)!);
      final year = _parseYearToken(dayMonthYear.group(3)!);
      final iso = _fmtYmd(year, mon, day);
      if (iso != null) return iso;
    }
    final monthDayYear = RegExp(
      r'^([a-zñ]+)\s+(\d{1,2})\s+(\d{4})$',
    ).firstMatch(s);
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
