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
  /// Abre crear conejo + relleno por voz (opcionalmente toda la frase en una ráfaga).
  createRabbitVoiceForm,
  listRabbits,
  listRabbitsDetailed,
  openDashboard,
  showSensors,
  getRabbitCount,
  getRabbitWeightById,
  getLatestWeightEvents,
  getRabbitWeightHistory,
  weightByName,
  /// Pedir eliminación (requiere confirmación por voz en el ViewModel).
  deleteRabbitRequest,
  /// Actualizar conejo (p. ej. peso) por nombre.
  updateRabbitVoice,
  /// Ver datos de un conejo por nombre («información de X», «ver conejo X», «datos de X»).
  viewRabbitInfo,
}
