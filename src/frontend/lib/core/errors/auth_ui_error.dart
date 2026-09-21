/// User-facing auth error. Technical codes stay in [technicalCode], never in UI copy.
enum AuthUiKind {
  invalidCredentials,
  emailNotVerified,
  emailAlreadyRegistered,
  verificationCodeInvalid,
  verificationCodeExpired,
  resetCodeInvalid,
  resetCodeExpired,
  tooManyAttempts,
  network,
  server,
  unknown,
}

class AuthUiError {
  const AuthUiError({
    required this.kind,
    required this.title,
    required this.message,
    required this.action,
    this.technicalCode,
  });

  final AuthUiKind kind;
  final String title;
  final String message;
  final String action;

  /// Backend/API code for logs and tests. Not shown in the UI.
  final String? technicalCode;
}
