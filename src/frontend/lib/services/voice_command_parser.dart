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

    // --- Create rabbit (keep) ---
    if (_anyWord(words, _createVerbs) && _anyWord(words, _rabbitNouns)) {
      return VoiceCommand.createRabbit;
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

  static const _createVerbs = {'crear', 'registrar', 'agregar'};
  static const _rabbitNouns = {'conejo', 'conejos'};
  static const _listVerbs = {'ver', 'mostrar', 'listar'};
  static const _sensorKeywords = {'sensor', 'sensores', 'temperatura', 'agua'};
  static const _dashboardKeywords = {'dashboard', 'panel'};
  static const _countWords = {'cuantos', 'cuántos'};

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
