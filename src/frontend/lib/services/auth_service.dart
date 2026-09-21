import 'dart:convert';

import '../core/errors/api_exception.dart';
import '../core/network/api_client.dart';
import '../models/auth_bootstrap.dart';
import 'auth_token_storage.dart';
import 'device_credential_contract.dart';

/// Backend auth: bootstrap, login, refresh. Refresh token on disk; access in [ApiClient] only.
class AuthService implements DeviceCredentialAuthApi {
  AuthService({
    required ApiClient apiClient,
    AuthTokenStorage? tokenStorage,
  })  : _api = apiClient,
        _storage = tokenStorage ?? AuthTokenStorage();

  final ApiClient _api;
  final AuthTokenStorage _storage;

  /// Invoked after a failed refresh on the 401 path (tokens already cleared).
  void Function()? onSessionInvalid;

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
    if (refresh == null || refresh.isEmpty) {
      await _endSessionAfterFailedRefresh();
      return false;
    }
    final ok = await refreshToken(refresh);
    if (!ok) {
      await _endSessionAfterFailedRefresh();
    }
    return ok;
  }

  Future<void> _endSessionAfterFailedRefresh() async {
    await clearSession();
    onSessionInvalid?.call();
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
  Future<void> register(
      {required String email, required String password}) async {
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

  /// POST `/api/auth/verify-email-code/`
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    await _api.post(
      '/api/auth/verify-email-code/',
      body: jsonEncode({
        'email': email.trim(),
        'code': code.trim(),
      }),
      headers: {'Accept': 'application/json'},
      includeAuthHeader: false,
    );
  }

  Future<void> clearSession() async {
    _api.accessToken = null;
    await _storage.writeRefreshToken(null);
  }

  /// POST `/api/auth/logout/` with current refresh when possible, then always clear local tokens.
  Future<void> logout() async {
    var refresh = await _storage.readRefreshToken();
    try {
      if (refresh != null && refresh.isNotEmpty) {
        if (_api.accessToken == null || _api.accessToken!.isEmpty) {
          await refreshToken(refresh);
          refresh = await _storage.readRefreshToken() ?? refresh;
        }
        if (_api.accessToken != null && _api.accessToken!.isNotEmpty) {
          await _api.post(
            '/api/auth/logout/',
            body: jsonEncode({'refresh': refresh}),
            headers: {'Accept': 'application/json'},
            includeAuthHeader: true,
          );
        }
      }
    } catch (_) {
      // Spec: if remote logout fails, still drop the local session.
    } finally {
      await clearSession();
    }
  }

  /// POST `/api/auth/password-reset/request/` — generic success even if email unknown.
  Future<void> requestPasswordReset({required String email}) async {
    await _api.post(
      '/api/auth/password-reset/request/',
      body: jsonEncode({'email': email.trim()}),
      headers: {'Accept': 'application/json'},
      includeAuthHeader: false,
    );
  }

  /// POST `/api/auth/password-reset/confirm/`
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _api.post(
      '/api/auth/password-reset/confirm/',
      body: jsonEncode({
        'email': email.trim(),
        'code': code.trim(),
        'new_password': newPassword,
      }),
      headers: {'Accept': 'application/json'},
      includeAuthHeader: false,
    );
  }

  /// GET `/api/users/biometric-status/` — server flag only.
  Future<bool> fetchBiometricEnabled() async {
    final raw = await _api.get(
      '/api/users/biometric-status/',
      headers: {'Accept': 'application/json'},
    );
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map['biometric_enabled'] == true;
  }

  /// PUT `/api/users/biometric-status/` — boolean flag; never biometric samples.
  Future<void> updateBiometricEnabled(bool enabled) async {
    await _api.put(
      '/api/users/biometric-status/',
      body: jsonEncode({'biometric_enabled': enabled}),
      headers: {'Accept': 'application/json'},
    );
  }

  @override
  Future<String> enrollDeviceCredential({
    required String publicKey,
    String? deviceLabel,
  }) async {
    final raw = await _api.post(
      '/api/auth/device-credentials/',
      body: jsonEncode({
        'public_key': publicKey,
        if (deviceLabel != null && deviceLabel.isNotEmpty)
          'device_label': deviceLabel,
      }),
      headers: {'Accept': 'application/json'},
    );
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final id = map['id'] as String?;
    if (id == null || id.isEmpty) {
      throw ApiException('Respuesta de enrolamiento inválida', statusCode: 201);
    }
    return id;
  }

  @override
  Future<({String nonce, String expiresAt})> requestDeviceChallenge({
    required String credentialId,
  }) async {
    final raw = await _api.post(
      '/api/auth/device-credentials/challenge/',
      body: jsonEncode({'credential_id': credentialId}),
      headers: {'Accept': 'application/json'},
      includeAuthHeader: false,
    );
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final nonce = map['nonce'] as String?;
    final expiresAt = map['expires_at'] as String?;
    if (nonce == null ||
        nonce.isEmpty ||
        expiresAt == null ||
        expiresAt.isEmpty) {
      throw ApiException('Respuesta de challenge inválida', statusCode: 200);
    }
    return (nonce: nonce, expiresAt: expiresAt);
  }

  @override
  Future<void> loginWithDeviceCredential({
    required String credentialId,
    required String nonce,
    required String signature,
  }) async {
    _api.accessToken = null;
    final raw = await _api.post(
      '/api/auth/device-credentials/login/',
      body: jsonEncode({
        'credential_id': credentialId,
        'nonce': nonce,
        'signature': signature,
      }),
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

  @override
  Future<void> revokeDeviceCredential(String credentialId) async {
    await _api.delete(
      '/api/auth/device-credentials/$credentialId/',
      headers: {'Accept': 'application/json'},
    );
  }

  Future<String?> readDeviceCredentialId() => _storage.readDeviceCredentialId();

  Future<void> writeDeviceCredentialId(String? value) =>
      _storage.writeDeviceCredentialId(value);

  Future<String?> readEnrolledUserHint() => _storage.readEnrolledUserHint();

  Future<void> writeEnrolledUserHint(String? value) =>
      _storage.writeEnrolledUserHint(value);
}
