import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists only the refresh token. Access token stays in memory ([ApiClient]).
class AuthTokenStorage {
  AuthTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _refreshKey = 'cunismart_refresh_token';

  final FlutterSecureStorage _storage;

  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  Future<void> writeRefreshToken(String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: _refreshKey);
    } else {
      await _storage.write(key: _refreshKey, value: value);
    }
  }
}
