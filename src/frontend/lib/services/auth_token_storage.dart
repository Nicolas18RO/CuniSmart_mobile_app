import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_credential_contract.dart';

/// Persists the refresh token plus local device-credential hints.
/// Access token stays in memory ([ApiClient]). Never stores a password.
class AuthTokenStorage implements DeviceCredentialLocalStore {
  AuthTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(),
        _memory = null;

  /// In-process map for unit tests (no platform channel).
  AuthTokenStorage.inMemory()
      : _storage = null,
        _memory = <String, String>{};

  static const String _refreshKey = 'cunismart_refresh_token';
  static const String _credentialIdKey = 'cunismart_device_credential_id';
  static const String _userHintKey = 'cunismart_enrolled_user_hint';

  final FlutterSecureStorage? _storage;
  final Map<String, String>? _memory;

  Future<String?> readRefreshToken() async => _read(_refreshKey);

  Future<void> writeRefreshToken(String? value) => _write(_refreshKey, value);

  @override
  Future<String?> readDeviceCredentialId() => _read(_credentialIdKey);

  @override
  Future<void> writeDeviceCredentialId(String? value) =>
      _write(_credentialIdKey, value);

  @override
  Future<String?> readEnrolledUserHint() => _read(_userHintKey);

  @override
  Future<void> writeEnrolledUserHint(String? value) =>
      _write(_userHintKey, value);

  Future<String?> _read(String key) async {
    if (_memory != null) {
      return _memory[key];
    }
    return _storage!.read(key: key);
  }

  Future<void> _write(String key, String? value) async {
    if (_memory != null) {
      if (value == null || value.isEmpty) {
        _memory.remove(key);
      } else {
        _memory[key] = value;
      }
      return;
    }
    if (value == null || value.isEmpty) {
      await _storage!.delete(key: key);
    } else {
      await _storage!.write(key: key, value: value);
    }
  }
}
