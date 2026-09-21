/// Formato numérico compartido entre voz (TTS) y [VoiceAIEngine].
class VoiceSpeechFormat {
  VoiceSpeechFormat._();

  static String doubleForSpeech(double v) {
    if (v == v.roundToDouble()) {
      return v.round().toString();
    }
    return v.toStringAsFixed(1);
  }

  static String kgComma(double v) => doubleForSpeech(v).replaceAll('.', ',');
}
