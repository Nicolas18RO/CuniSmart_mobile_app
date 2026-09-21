import 'package:frontend/services/device_credential_contract.dart';

/// G10.2/G10.3 — fake de firma de dispositivo (opción C).
class FakeDeviceCredentialSigner implements DeviceCredentialSigner {
  FakeDeviceCredentialSigner({
    this.publicKey = 'TEST_DEVICE_PUBLIC_KEY',
    this.credentialId,
  });

  final String publicKey;
  String? credentialId;
  final List<String> signedNonces = [];
  bool invalidatedByOsEnrollment = false;

  @override
  Future<String> exportPublicKey() async => publicKey;

  @override
  Future<String> sign(String nonce) async {
    if (invalidatedByOsEnrollment) {
      throw StateError('device_key_invalidated');
    }
    signedNonces.add(nonce);
    return 'sig-of-$nonce';
  }
}
