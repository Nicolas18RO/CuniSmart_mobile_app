import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

import 'package:frontend/services/device_authenticator.dart';

/// Outcomes that [local_auth] 2.3.0 can actually surface to Dart.
///
/// Android maps both user-cancel (`ERROR_CANCELED`) and generic auth failure
/// to [AuthResult.failure], so [failed] covers both. Do not invent a separate
/// cancel code: the plugin does not emit one.
enum FakeBiometricAuthOutcome {
  success,
  failed,
  lockedOut,
  notEnrolled,
  platformError,
}

class FakeDeviceAuthenticator implements DeviceAuthenticator {
  FakeDeviceAuthenticator({
    this.available = true,
    this.authSucceeds = true,
    this.outcome,
  });

  bool available;
  bool authSucceeds;
  FakeBiometricAuthOutcome? outcome;
  int authenticateCalls = 0;
  String? lastReason;

  FakeBiometricAuthOutcome get _resolvedOutcome {
    if (outcome != null) return outcome!;
    return authSucceeds
        ? FakeBiometricAuthOutcome.success
        : FakeBiometricAuthOutcome.failed;
  }

  @override
  Future<bool> canAuthenticate() async => available;

  @override
  Future<bool> authenticate({required String reason}) async {
    authenticateCalls += 1;
    lastReason = reason;
    switch (_resolvedOutcome) {
      case FakeBiometricAuthOutcome.success:
        return true;
      case FakeBiometricAuthOutcome.failed:
        return false;
      case FakeBiometricAuthOutcome.lockedOut:
        throw PlatformException(
          code: auth_error.lockedOut,
          message:
              'The operation was canceled because the API is locked out due to too many attempts.',
        );
      case FakeBiometricAuthOutcome.notEnrolled:
        throw PlatformException(
          code: auth_error.notEnrolled,
          message: 'No Biometrics enrolled on this device.',
        );
      case FakeBiometricAuthOutcome.platformError:
        throw PlatformException(
          code: 'no_fragment_activity',
          message:
              'local_auth plugin requires activity to be a FragmentActivity.',
        );
    }
  }
}
