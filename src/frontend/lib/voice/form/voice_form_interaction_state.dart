/// Estado explícito de interacción por voz en el alta de conejo (DESIGN §3).
enum VoiceFormInteractionState {
  idle,
  askingName,
  askingBreed,
  askingSex,
  askingBirthDate,
  askingWeight,
  askingStatus,
  askingNotes,
  confirming,
  saving,
  success,
  error,
  cancelled,
}
