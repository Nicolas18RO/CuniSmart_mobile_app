/// G10.3 — contrato de credencial de dispositivo (opción C).
///
/// No es el flag [biometric_enabled]. No almacena contraseña ni muestras.
library;

abstract class DeviceCredentialAuthApi {
  Future<String> enrollDeviceCredential({
    required String publicKey,
    String? deviceLabel,
  });

  Future<({String nonce, String expiresAt})> requestDeviceChallenge({
    required String credentialId,
  });

  Future<void> loginWithDeviceCredential({
    required String credentialId,
    required String nonce,
    required String signature,
  });

  Future<void> revokeDeviceCredential(String credentialId);
}

abstract class DeviceCredentialLocalStore {
  Future<String?> readDeviceCredentialId();
  Future<void> writeDeviceCredentialId(String? value);
  Future<String?> readEnrolledUserHint();
  Future<void> writeEnrolledUserHint(String? value);
}

abstract class BiometricLoginViewModelApi {
  bool get canOfferBiometricLogin;
  String? get enrolledUserHint;
  Future<bool> enrollDeviceCredential();
  Future<bool> loginWithBiometric();
}

abstract class DeviceCredentialSigner {
  Future<String> exportPublicKey();
  Future<String> sign(String nonce);
}
