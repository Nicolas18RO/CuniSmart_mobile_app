/// Reusable mutation state for forms (create/update/delete).
sealed class SubmitState {
  const SubmitState();
}

final class SubmitIdle extends SubmitState {
  const SubmitIdle();
}

final class SubmitInProgress extends SubmitState {
  const SubmitInProgress();
}

final class SubmitFailed extends SubmitState {
  const SubmitFailed(this.message);

  final String message;
}
