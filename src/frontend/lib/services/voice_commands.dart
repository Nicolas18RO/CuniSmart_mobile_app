/// Desambiguación léxica para [VoiceCommand.showSensors] (solo texto; sin I/O).
enum VoiceSensorLexicalKind {
  temperature,
  water,
  general,
}

/// High-level intents produced from Spanish voice phrases.
///
/// Values map 1:1 to supported utterances in [VoiceCommandParser]; no UI wiring yet.
enum VoiceCommand {
  createRabbit,
  listRabbits,
  listRabbitsDetailed,
  openDashboard,
  showSensors,
  getRabbitCount,
  getRabbitWeightById,
  getLatestWeightEvents,
  getRabbitWeightHistory,
  weightByName,
}
