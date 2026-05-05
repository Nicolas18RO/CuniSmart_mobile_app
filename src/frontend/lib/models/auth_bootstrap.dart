/// Response from `GET /api/auth/bootstrap/`.
class BootstrapResult {
  const BootstrapResult({
    required this.sessionValid,
    required this.authRequired,
    required this.biometricAvailable,
  });

  final bool sessionValid;
  final bool authRequired;
  final bool biometricAvailable;

  factory BootstrapResult.fromJson(Map<String, dynamic> json) {
    return BootstrapResult(
      sessionValid: json['session_valid'] == true,
      authRequired: json['auth_required'] == true,
      biometricAvailable: json['biometric_available'] == true,
    );
  }
}
