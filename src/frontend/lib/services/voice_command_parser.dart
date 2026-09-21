import 'voice_commands.dart';

/// Intent-based Spanish voice → [VoiceCommand] mapping.
///
/// Normalization keeps letters **and digits** (e.g. `BoxPony01`). Matching order
/// avoids confusing weight intents with rabbit-list intents.
class VoiceCommandParser {
  const VoiceCommandParser();

  static final _punctuationAndNoise =
      RegExp(r'[^\p{L}\p{N}\s]+', unicode: true);
  static final _wordPattern = RegExp(r'\p{L}+', unicode: true);
  static final _rabbitIdPattern = RegExp(r'\bconejo\s+(\d+)\b');
  static final _latestWeightsPattern = RegExp(r'\bultimos\s+(\d+)\s+pesos\b');

  static final _nameAfterCuantoPesa = RegExp(
    r'\bcuanto\s+pesa\s+([\p{L}\p{N}]+)',
    unicode: true,
  );
  static final _nameAfterPesoDe = RegExp(
    r'\bpeso\s+de\s+([\p{L}\p{N}]+)',
    unicode: true,
  );
  static final _nameAfterPesa = RegExp(
    r'\bpesa\s+([\p{L}\p{N}]+)',
    unicode: true,
  );
  static final _nameAfterPeso = RegExp(
    r'\bpeso\s+([\p{L}\p{N}]+)',
    unicode: true,
  );

  static const _notRabbitNameTokens = {
    'del',
    'de',
    'la',
    'el',
    'los',
    'las',
    'lo',
    'un',
    'una',
    'conejos',
    'conejo',
    'pesos',
    'peso',
    'ver',
    'mostrar',
    'listar',
    'eventos',
    'historial',
    'ultimos',
    'últimos',
    'cuantos',
    'cuántos',
    'cuanto',
    'kilogramos',
    'kilos',
  };

  VoiceCommand? parse(String recognizedText) {
    final n = _normalize(recognizedText);
    if (n.isEmpty) return null;

    final words = _wordSet(n);

    // --- Ver ficha (prioridad máxima; antes de peso / lista / CRUD) ---
    if (_tryExtractViewRabbitInfoName(n) != null) {
      return VoiceCommand.viewRabbitInfo;
    }

    // --- Count (keep) ---
    if (_anyWord(words, _countWords) && words.contains('conejos')) {
      return VoiceCommand.getRabbitCount;
    }

    // --- Weight by rabbit id (keep; must beat name / list heuristics) ---
    if (words.contains('peso') && _rabbitIdPattern.hasMatch(n)) {
      return VoiceCommand.getRabbitWeightById;
    }

    // --- Weight history by id (keep) ---
    if ((_rabbitIdPattern.hasMatch(n) && words.contains('pesos')) ||
        (_rabbitIdPattern.hasMatch(n) && words.contains('historial'))) {
      return VoiceCommand.getRabbitWeightHistory;
    }

    // 1) Weight by name (most specific among “free text” intents)
    final extractedName = extractRabbitName(recognizedText);
    if (extractedName != null && !_isLatestWeightsIntent(n, words)) {
      return VoiceCommand.weightByName;
    }

    // 2) Latest weight events
    if (_isLatestWeightsIntent(n, words)) {
      return VoiceCommand.getLatestWeightEvents;
    }

    // 3) Detailed rabbit list (before simple list / generic “conejos”)
    if (_isListRabbitsDetailedIntent(n)) {
      return VoiceCommand.listRabbitsDetailed;
    }

    // 4) Simple rabbit list
    if (_isSimpleListRabbitsIntent(n)) {
      return VoiceCommand.listRabbits;
    }

    // --- CRUD por voz ---
    if (_isCreateRabbitVoiceFormIntent(n, words)) {
      return VoiceCommand.createRabbitVoiceForm;
    }
    if (_isDeleteRabbitIntent(n, words)) {
      return VoiceCommand.deleteRabbitRequest;
    }
    if (_isUpdateRabbitIntent(n, words)) {
      return VoiceCommand.updateRabbitVoice;
    }

    // --- Sensors / dashboard (keep) ---
    if (_anyWord(words, _sensorKeywords)) {
      return VoiceCommand.showSensors;
    }
    if (_anyWord(words, _dashboardKeywords)) {
      return VoiceCommand.openDashboard;
    }

    // Generic rabbits (fallback)
    if (_anyWord(words, _listVerbs) || _anyWord(words, _rabbitNouns)) {
      return VoiceCommand.listRabbits;
    }

    return null;
  }

  static const _rabbitNouns = {'conejo', 'conejos'};
  static const _listVerbs = {'ver', 'mostrar', 'listar'};
  static const _sensorKeywords = {'sensor', 'sensores', 'temperatura', 'agua'};
  static const _dashboardKeywords = {'dashboard', 'panel'};
  static const _countWords = {'cuantos', 'cuántos'};
  static const _deleteVerbs = {'eliminar', 'borrar', 'quitar'};
  static const _updateVerbs = {'editar', 'actualizar', 'modificar'};

  static final _weightAfterPeso = RegExp(
    r'\bpeso\s+([\d]+(?:[.,][\d]+)?)\b',
    unicode: true,
  );
  static final _breedAfterRaza = RegExp(
    r'\braza\s+([\p{L}\p{N}]+)',
    unicode: true,
  );

  bool _isDeleteRabbitIntent(String n, Set<String> words) {
    if (!_anyWord(words, _deleteVerbs)) return false;
    if (!words.contains('conejo') && !n.contains('conejo ')) return false;
    return extractDeleteRabbitNameQuery(n) != null;
  }

  bool _isUpdateRabbitIntent(String n, Set<String> words) {
    if (!_anyWord(words, _updateVerbs)) return false;
    if (!words.contains('conejo') && !n.contains('conejo ')) return false;
    return extractUpdateRabbitNameQuery(n) != null;
  }

  bool _isCreateRabbitVoiceFormIntent(String n, Set<String> words) {
    if (_blocksCreateRabbitForm(n)) return false;
    if (!RegExp(r'\b(?:crear|registrar|agregar)\b').hasMatch(n)) return false;
    return words.contains('conejo') || words.contains('conejos');
  }

  /// Consultas de ficha / lista verbal que no deben clasificarse como alta.
  bool _blocksCreateRabbitForm(String n) {
    if (_tryExtractViewRabbitInfoName(n) != null) return true;
    if (RegExp(r'\binformaci[oó]n\b').hasMatch(n)) return true;
    if (RegExp(r'\bdatos\b').hasMatch(n)) return true;
    return false;
  }

  /// Patrones: `información (de)? NAME`, `datos (de)? NAME`, `ver conejo NAME`, `ver NAME`.
  String? extractViewRabbitInfoNameQuery(String recognizedText) {
    return _tryExtractViewRabbitInfoName(_normalize(recognizedText));
  }

  static const _verDirectExcludeFirst = {
    'conejos',
    'conejo',
    'los',
    'las',
    'el',
    'la',
    'pesos',
    'peso',
    'sensores',
    'sensor',
    'dashboard',
    'panel',
    'ultimos',
    'últimos',
    'mis',
    'lista',
    'eventos',
    'datos',
    'informacion',
    'información',
    'mostrar',
    'listar',
    'temperatura',
    'agua',
    'nivel',
    'humedad',
  };

  String? _trimInfoNameTail(String tail) {
    var t = tail.trim();
    if (t.isEmpty) return null;
    for (final kw in [' raza ', ' peso ', ' notas', ' macho', ' hembra']) {
      final i = t.indexOf(kw);
      if (i >= 0) t = t.substring(0, i).trim();
    }
    return t.isEmpty ? null : t;
  }

  String? _tryExtractViewRabbitInfoName(String n) {
    // 1) información (del | de)? NAME  —  también «información lucas» sin «de».
    final info = RegExp(
      r'\binformaci[oó]n\s+(?:(?:del|de)\s+)?(.+)$',
      unicode: true,
    ).firstMatch(n);
    if (info != null) {
      final name = _trimInfoNameTail(info.group(1) ?? '');
      if (name != null) return name;
    }

    // 2) datos (del | de)? NAME
    final datos = RegExp(
      r'\bdatos\s+(?:(?:del|de)\s+)?(.+)$',
      unicode: true,
    ).firstMatch(n);
    if (datos != null) {
      final raw = (datos.group(1) ?? '').trim().toLowerCase();
      if (!raw.startsWith('sensor') &&
          !raw.startsWith('sensores') &&
          !raw.startsWith('del sensor')) {
        final name = _trimInfoNameTail(datos.group(1) ?? '');
        if (name != null) return name;
      }
    }

    // 3) ver conejo NAME
    final verConejo = RegExp(
      r'\bver\s+conejo\s+(.+)$',
      unicode: true,
    ).firstMatch(n);
    if (verConejo != null) {
      final name = _trimInfoNameTail(verConejo.group(1) ?? '');
      if (name != null) return name;
    }

    // 4) ver NAME (no «ver conejos», «ver pesos», etc.)
    final verDirect = RegExp(r'^ver\s+(.+)$', unicode: true).firstMatch(n);
    if (verDirect != null) {
      var tail = (verDirect.group(1) ?? '').trim();
      if (tail.isEmpty) return null;
      final firstTok = tail.split(RegExp(r'\s+')).first.toLowerCase();
      if (!_verDirectExcludeFirst.contains(firstTok)) {
        return _trimInfoNameTail(tail);
      }
    }

    return null;
  }

  /// Texto tras «crear|registrar|agregar … conejo» (puede ser vacío).
  String extractCreateRabbitVoiceFormRemainder(String recognizedText) {
    final n = _normalize(recognizedText);
    final m = RegExp(
      r'^(?:crear|registrar|agregar)\s+(?:el\s+)?(?:conejo|conejos)\s*(.*)$',
    ).firstMatch(n);
    if (m == null) return '';
    return (m.group(1) ?? '').trim();
  }

  /// Nombre objetivo tras "eliminar|borrar|quitar ... conejo".
  String? extractDeleteRabbitNameQuery(String recognizedText) {
    return _extractNameAfterConejoVerb(
      recognizedText,
      RegExp(
        r'\b(?:eliminar|borrar|quitar)\s+(?:el\s+)?conejo\s+(.+)$',
        unicode: true,
      ),
    );
  }

  /// Nombre objetivo tras "editar|actualizar|modificar ... conejo".
  String? extractUpdateRabbitNameQuery(String recognizedText) {
    return _extractNameAfterConejoVerb(
      recognizedText,
      RegExp(
        r'\b(?:editar|actualizar|modificar)\s+(?:el\s+)?conejo\s+(.+)$',
        unicode: true,
      ),
    );
  }

  /// Peso opcional en frases de actualización ("... peso 3,5").
  double? extractVoiceWeightAfterPeso(String recognizedText) {
    final n = _normalize(recognizedText);
    final m = _weightAfterPeso.firstMatch(n);
    if (m == null) return null;
    final raw = (m.group(1) ?? '').replaceAll(',', '.');
    return double.tryParse(raw);
  }

  /// Raza opcional en "crear conejo X raza California".
  String? extractCreateRabbitBreed(String recognizedText) {
    final n = _normalize(recognizedText);
    final m = _breedAfterRaza.firstMatch(n);
    if (m == null) return null;
    return m.group(1)?.trim();
  }

  /// `male` / `female` para API.
  String? extractCreateRabbitSex(String recognizedText) {
    final n = _normalize(recognizedText);
    if (n.contains(' hembra')) return 'female';
    if (n.contains(' macho')) return 'male';
    return null;
  }

  /// Nombre (puede ser varias palabras) tras "crear|registrar|agregar ... conejo".
  String? extractCreateRabbitVoiceName(String recognizedText) {
    return _extractNameAfterConejoVerb(
      recognizedText,
      RegExp(
        r'\b(?:crear|registrar|agregar)\s+(?:el\s+)?conejo\s+(.+)$',
        unicode: true,
      ),
    );
  }

  String? _extractNameAfterConejoVerb(String recognizedText, RegExp re) {
    final n = _normalize(recognizedText);
    final m = re.firstMatch(n);
    if (m == null) return null;
    var tail = (m.group(1) ?? '').trim();
    if (tail.isEmpty) return null;
    for (final kw in [' raza ', ' peso ', ' macho', ' hembra']) {
      final i = tail.indexOf(kw);
      if (i >= 0) tail = tail.substring(0, i).trim();
    }
    if (tail.isEmpty) return null;
    return tail;
  }

  /// Extracts a rabbit name token for [VoiceCommand.weightByName].
  String? extractRabbitName(String recognizedText) {
    final n = _normalize(recognizedText);
    if (n.isEmpty) return null;

    final patterns = [
      _nameAfterCuantoPesa,
      _nameAfterPesoDe,
      _nameAfterPesa,
      _nameAfterPeso,
    ];
    for (final re in patterns) {
      final m = re.firstMatch(n);
      if (m == null) continue;
      final captured = (m.group(1) ?? '').trim().toLowerCase();
      if (captured.isEmpty) continue;
      if (_notRabbitNameTokens.contains(captured)) continue;
      return captured;
    }
    return null;
  }

  /// Backwards-compatible alias.
  String? extractWeightName(String recognizedText) =>
      extractRabbitName(recognizedText);

  int? extractRabbitId(String recognizedText) {
    final n = _normalize(recognizedText);
    final m = _rabbitIdPattern.firstMatch(n);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
  }

  int? extractLatestWeightLimit(String recognizedText) {
    final n = _normalize(recognizedText);
    final m = _latestWeightsPattern.firstMatch(n);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
  }

  /// Sub-intent para TTS de sensores; usa la misma tokenización que [parse].
  VoiceSensorLexicalKind lexicalSensorReadout(String recognizedText) {
    final n = _normalize(recognizedText);
    final words = _wordSet(n);
    if (words.contains('temperatura')) {
      return VoiceSensorLexicalKind.temperature;
    }
    if (words.contains('agua') || words.contains('nivel')) {
      return VoiceSensorLexicalKind.water;
    }
    return VoiceSensorLexicalKind.general;
  }

  String _normalize(String raw) {
    var s = raw.toLowerCase().trim();
    s = s.replaceAll(_punctuationAndNoise, ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.trim();
  }

  Set<String> _wordSet(String normalized) {
    return _wordPattern
        .allMatches(normalized)
        .map((m) => m.group(0)!.toLowerCase())
        .toSet();
  }

  bool _anyWord(Set<String> words, Set<String> options) {
    for (final o in options) {
      if (words.contains(o)) return true;
    }
    return false;
  }

  bool _isLatestWeightsIntent(String n, Set<String> words) {
    if (words.contains('eventos') && words.contains('peso')) {
      return true;
    }
    if (_latestWeightsPattern.hasMatch(n)) {
      return true;
    }
    if (words.contains('ver') && words.contains('pesos')) {
      return true;
    }
    if (words.contains('mostrar') && words.contains('pesos')) {
      return true;
    }
    if ((n.contains('ultimos') || n.contains('últimos')) &&
        n.contains('pesos')) {
      return true;
    }
    return false;
  }

  bool _isListRabbitsDetailedIntent(String n) {
    if (n.contains('mis conejos')) return true;
    if (n.contains('listar conejos')) return true;
    if (n.contains('detalles') && n.contains('conejos')) return true;
    if (n.contains('informacion') && n.contains('conejos')) return true;
    if (n.contains('información') && n.contains('conejos')) return true;
    return false;
  }

  bool _isSimpleListRabbitsIntent(String n) {
    return n.contains('ver conejos') || n.contains('mostrar conejos');
  }
}
