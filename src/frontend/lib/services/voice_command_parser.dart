import 'voice_commands.dart';

/// Maps recognized Spanish speech to a [VoiceCommand] using keyword rules.
///
/// Text is normalized (lowercase, trim, punctuation removed). Matching uses
/// whole words to avoid accidental hits (e.g. "ver" inside "televisor").
/// More specific rules are checked before generic ones.
class VoiceCommandParser {
  const VoiceCommandParser();

  static final _punctuationAndNoise = RegExp(r'[^\p{L}\p{N}\s]+', unicode: true);
  static final _wordPattern = RegExp(r'\p{L}+', unicode: true);

  VoiceCommand? parse(String recognizedText) {
    final n = _normalize(recognizedText);
    if (n.isEmpty) return null;

    final words = _wordSet(n);

    // 1. Most specific: intent verb + rabbit
    if (_anyWord(words, _createVerbs) && _anyWord(words, _rabbitNouns)) {
      return VoiceCommand.createRabbit;
    }
    // 2. Sensor / IoT vocabulary
    if (_anyWord(words, _sensorKeywords)) {
      return VoiceCommand.showSensors;
    }
    // 3. Dashboard / panel
    if (_anyWord(words, _dashboardKeywords)) {
      return VoiceCommand.openDashboard;
    }
    // 4. Generic list / rabbits
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
}
