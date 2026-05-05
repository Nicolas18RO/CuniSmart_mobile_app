import 'dart:convert';

import '../core/errors/api_exception.dart';
import '../core/network/api_client.dart';
import '../models/auth_bootstrap.dart';
import 'auth_token_storage.dart';

/// Backend auth: bootstrap, login, refresh. Refresh token on disk; access in [ApiClient] only.
class AuthService {
  AuthService({
    required ApiClient apiClient,
    AuthTokenStorage? tokenStorage,
  })  : _api = apiClient,
        _storage = tokenStorage ?? AuthTokenStorage();

  final ApiClient _api;
  final AuthTokenStorage _storage;

  /// Restore access from stored refresh (if any), then `GET /api/auth/bootstrap/`.
  /// On any failure → logged-out shape (treat as unauthenticated).
  Future<BootstrapResult> bootstrap() async {
    try {
      _api.accessToken = null;
      final refresh = await _storage.readRefreshToken();
      if (refresh != null && refresh.isNotEmpty) {
        final ok = await refreshToken(refresh);
        if (!ok) {
          await clearSession();
        }
      }
      final includeAuth =
          _api.accessToken != null && _api.accessToken!.isNotEmpty;
      final raw = await _api.get(
        '/api/auth/bootstrap/',
        headers: {'Accept': 'application/json'},
        includeAuthHeader: includeAuth,
      );
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return BootstrapResult.fromJson(map);
    } catch (_) {
      await clearSession();
      return const BootstrapResult(
        sessionValid: false,
        authRequired: true,
        biometricAvailable: false,
      );
    }
  }

  /// Uses refresh token from secure storage (e.g. after 401).
  Future<bool> refreshFromStorage() async {
    final refresh = await _storage.readRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    return refreshToken(refresh);
  }

  /// POST `/api/auth/token/refresh/` — updates in-memory access; persists new refresh if rotated.
  Future<bool> refreshToken(String refresh) async {
    try {
      final raw = await _api.post(
        '/api/auth/token/refresh/',
        body: jsonEncode({'refresh': refresh}),
        headers: {'Accept': 'application/json'},
        includeAuthHeader: false,
      );
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final access = map['access'] as String?;
      final newRefresh = map['refresh'] as String?;
      if (access == null || access.isEmpty) return false;
      _api.accessToken = access;
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await _storage.writeRefreshToken(newRefresh);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> login({required String email, required String password}) async {
    _api.accessToken = null;
    final raw = await _api.post(
      '/api/auth/login/',
      body: jsonEncode({'email': email.trim(), 'password': password}),
      headers: {'Accept': 'application/json'},
      includeAuthHeader: false,
    );
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final access = map['access'] as String?;
    final refresh = map['refresh'] as String?;
    if (access == null ||
        access.isEmpty ||
        refresh == null ||
        refresh.isEmpty) {
      throw ApiException('Respuesta de login inválida', statusCode: 200);
    }
    _api.accessToken = access;
    await _storage.writeRefreshToken(refresh);
  }

  /// POST `/api/auth/register/` — creates account and triggers email verification email.
  Future<void> register({required String email, required String password}) async {
    await _api.post(
      '/api/auth/register/',
      body: jsonEncode({'email': email.trim(), 'password': password}),
      headers: {'Accept': 'application/json'},
      includeAuthHeader: false,
    );
  }

  /// POST `/api/auth/resend-verification/`
  Future<void> resendVerificationEmail({required String email}) async {
    await _api.post(
      '/api/auth/resend-verification/',
      body: jsonEncode({'email': email.trim()}),
      headers: {'Accept': 'application/json'},
      includeAuthHeader: false,
    );
  }

  Future<void> clearSession() async {
    _api.accessToken = null;
    await _storage.writeRefreshToken(null);
  }
}
