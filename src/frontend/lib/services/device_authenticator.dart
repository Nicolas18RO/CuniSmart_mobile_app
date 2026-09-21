import 'package:local_auth/local_auth.dart';

/// Device PIN / biometrics. Never sends biometric samples to the backend.
abstract class DeviceAuthenticator {
  Future<bool> canAuthenticate();

  Future<bool> authenticate({required String reason});
}

class LocalDeviceAuthenticator implements DeviceAuthenticator {
  LocalDeviceAuthenticator({LocalAuthentication? plugin})
      : _plugin = plugin ?? LocalAuthentication();

  final LocalAuthentication _plugin;

  @override
  Future<bool> canAuthenticate() async {
    try {
      return await _plugin.canCheckBiometrics ||
          await _plugin.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    return _plugin.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(
        biometricOnly: false,
        stickyAuth: true,
      ),
    );
  }
}
