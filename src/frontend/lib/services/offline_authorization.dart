import 'package:flutter/services.dart';

typedef BootTime = ({
  int bootCount,
  int elapsedMilliseconds,
  String installationId
});
typedef ReadBootTime = Future<BootTime?> Function();

Future<BootTime?> readAndroidBootTime() async {
  const channel = MethodChannel('cunismart/session_clock');
  try {
    final data = await channel.invokeMapMethod<String, Object>('read');
    final boot = data?['bootCount'];
    final elapsed = data?['elapsedMilliseconds'];
    final installation = data?['installationId'];
    if (boot is! int ||
        boot < 0 ||
        elapsed is! int ||
        elapsed < 0 ||
        installation is! String ||
        installation.isEmpty) return null;
    return (
      bootCount: boot,
      elapsedMilliseconds: elapsed,
      installationId: installation
    );
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

class OfflineAuthorization {
  const OfflineAuthorization({
    required this.ownerId,
    required this.biometricRequired,
    required this.verifiedAt,
    required this.anchor,
  });

  static const duration = Duration(hours: 24);

  final int ownerId;
  final bool biometricRequired;
  final DateTime verifiedAt;
  final BootTime anchor;

  Duration remaining(BootTime? current) {
    if (current == null ||
        current.bootCount != anchor.bootCount ||
        current.installationId != anchor.installationId) {
      return Duration.zero;
    }
    final elapsed = current.elapsedMilliseconds - anchor.elapsedMilliseconds;
    if (elapsed < 0 || elapsed >= duration.inMilliseconds) return Duration.zero;
    return duration - Duration(milliseconds: elapsed);
  }

  Map<String, Object> toJson() => {
        'user_id': ownerId,
        'is_verified': true,
        'biometric_required': biometricRequired,
        'last_remote_verification_at': verifiedAt.toIso8601String(),
        'offline_authorization_expires_at':
            verifiedAt.add(duration).toIso8601String(),
        'boot_count': anchor.bootCount,
        'elapsed_ms': anchor.elapsedMilliseconds,
        'installation_id': anchor.installationId,
      };

  static OfflineAuthorization? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final owner = json['user_id'];
    final boot = json['boot_count'];
    final elapsed = json['elapsed_ms'];
    final biometric = json['biometric_required'];
    final timestamp = json['last_remote_verification_at'];
    final installation = json['installation_id'];
    if (owner is! int ||
        owner <= 0 ||
        json['is_verified'] != true ||
        boot is! int ||
        boot < 0 ||
        elapsed is! int ||
        elapsed < 0 ||
        biometric is! bool ||
        timestamp is! String ||
        installation is! String ||
        installation.isEmpty) return null;
    final verifiedAt = DateTime.tryParse(timestamp);
    if (verifiedAt == null ||
        json['offline_authorization_expires_at'] !=
            verifiedAt.add(duration).toIso8601String()) {
      return null;
    }
    return OfflineAuthorization(
        ownerId: owner,
        biometricRequired: biometric,
        verifiedAt: verifiedAt,
        anchor: (
          bootCount: boot,
          elapsedMilliseconds: elapsed,
          installationId: installation
        ));
  }
}
