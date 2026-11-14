import 'dart:async';
import 'dart:convert';

import '../core/errors/api_exception.dart';
import '../core/network/api_client.dart';
import '../models/auth_bootstrap.dart';
import 'auth_token_storage.dart';
import 'device_credential_contract.dart';
import 'offline_authorization.dart';

enum SessionVerification {
  verified,
  temporaryFailure,
  definitiveRejection,
  identityMismatch,
  unverifiable
}

/// Backend auth: bootstrap, login, refresh. Refresh token on disk; access in [ApiClient] only.
class AuthService implements DeviceCredentialAuthApi {
  AuthService({
    required ApiClient apiClient,
    AuthTokenStorage? tokenStorage,
    ReadBootTime? readBootTime,
  })  : _api = apiClient,
        _storage = tokenStorage ?? AuthTokenStorage(),
        _readBootTime = readBootTime;

  final ApiClient _api;
  final AuthTokenStorage _storage;
  final ReadBootTime? _readBootTime;

  /// Invoked when the session is invalidated, before asynchronous cleanup.
  void Function()? onSessionInvalid;
  Future<SessionVerification>? _refreshInFlight;
  int _generation = 0;
  int _networkGeneration = 0;
  int? _ownerId;
  bool _biometricRequired = false;
  bool _remoteVerified = false;
  bool localDataUnlocked = false;
  bool offlineDeviceUnlockAvailable = true;
  Timer? _offlineExpiry;
  Future<SessionVerification>? _verificationInFlight;
  Future<void> _storageWrite = Future<void>.value();

  int get generation => _generation;
  int? get ownerId => _ownerId;
  bool get remoteVerified => _remoteVerified;
  bool get biometricRequired => _biometricRequired;
  bool get usesAccountAuthorization => _readBootTime != null;

  void markDisconnected() {
    _networkGeneration++;
    _remoteVerified = false;
    if (_ownerId != null) unawaited(_expireIfNeeded(_generation));
  }

  Future<void> _expireIfNeeded(int generation) async {
    if (await canAccessLocally() ||
        generation != _generation ||
        _remoteVerified) return;
    _invalidateMemory();
    onSessionInvalid?.call();
  }

  Future<void> _writeSession(Future<void> Function() action) {
    final next = _storageWrite.then((_) => action());
    _storageWrite =
        next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  SessionVerification _classify(ApiException error,
      {required bool refreshing}) {
    final status = error.statusCode;
    if (error.code == 'network' || (status != null && status >= 500)) {
      return SessionVerification.temporaryFailure;
    }
    const rejectedAccountCodes = {
      'inactive_user',
      'email_not_verified',
      'invalid_credentials',
    };
    if (status == 401 ||
        (refreshing &&
            status == 400 &&
            rejectedAccountCodes.contains(error.code)) ||
        (status == 403 && rejectedAccountCodes.contains(error.code))) {
      return SessionVerification.definitiveRejection;
    }
    return SessionVerification.unverifiable;
  }

  /// Restore access from stored refresh (if any), then `GET /api/auth/bootstrap/`.
  /// On any failure → logged-out shape (treat as unauthenticated).
  Future<BootstrapResult> bootstrap() async {
    if (usesAccountAuthorization) {
      final generation = _generation;
      try {
        if (await _storage.readRefreshToken() == null) return _loggedOut;
      } catch (_) {
        return _loggedOut;
      }
      final result = await verifySession();
      if (generation != _generation) return _loggedOut;
      if (result == SessionVerification.verified) {
        return BootstrapResult(
          sessionValid: true,
          authRequired: false,
          biometricAvailable: _biometricRequired,
        );
      }
      if (result == SessionVerification.temporaryFailure ||
          result == SessionVerification.unverifiable) {
        return _restoreOffline(generation);
      }
      return _loggedOut;
    }
    try {
      _api.accessToken = null;
      final refresh = await _storage.readRefreshToken();
      if (refresh != null && refresh.isNotEmpty) {
        final result = await _refreshOnce();
        if (result != SessionVerification.verified &&
            result != SessionVerification.definitiveRejection) {
          return _loggedOut;
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
      return _loggedOut;
    }
  }

  static const _loggedOut = BootstrapResult(
    sessionValid: false,
    authRequired: true,
    biometricAvailable: false,
  );

  Future<OfflineAuthorization?> _storedAuthorization() async {
    final raw = await _storage.readOfflineAuthorization();
    if (raw == null) return null;
    return OfflineAuthorization.fromJson(jsonDecode(raw));
  }

  Future<BootstrapResult> _restoreOffline(int generation) async {
    try {
      final refresh = await _storage.readRefreshToken();
      final authorization = await _storedAuthorization();
      final clock = await _readBootTime?.call();
      if (generation != _generation ||
          refresh == null ||
          refresh.isEmpty ||
          authorization == null ||
          (_ownerId != null && _ownerId != authorization.ownerId)) {
        return _loggedOut;
      }
      final remaining = authorization.remaining(clock);
      if (remaining == Duration.zero) return _loggedOut;
      _ownerId = authorization.ownerId;
      _biometricRequired = authorization.biometricRequired;
      _offlineExpiry?.cancel();
      _offlineExpiry = Timer(remaining, () {
        if (generation == _generation && !_remoteVerified) {
          _invalidateMemory();
          onSessionInvalid?.call();
        }
      });
      return BootstrapResult(
          sessionValid: true,
          authRequired: false,
          biometricAvailable: _biometricRequired,
          offline: true);
    } catch (_) {
      return _loggedOut;
    }
  }

  Future<bool> canAccessLocally() async {
    if (!usesAccountAuthorization) return true;
    if (_remoteVerified) return true;
    if (_ownerId == null) return false;
    if (_biometricRequired && !offlineDeviceUnlockAvailable) return false;
    return (await _restoreOffline(_generation)).sessionValid;
  }

  Future<SessionVerification> verifySession({bool refreshFirst = true}) {
    final running = _verificationInFlight;
    if (running != null) return running;
    final generation = _generation;
    _remoteVerified = false;
    late final Future<SessionVerification> attempt;
    attempt = _verifySession(generation, refreshFirst).whenComplete(() {
      if (identical(_verificationInFlight, attempt)) {
        _verificationInFlight = null;
      }
    });
    return _verificationInFlight = attempt;
  }

  Future<SessionVerification> _verifySession(
      int generation, bool refreshFirst) async {
    final network = _networkGeneration;
    try {
      final previous = await _storedAuthorization();
      final expected = _ownerId ?? previous?.ownerId;
      if (generation != _generation) {
        return SessionVerification.identityMismatch;
      }
      if (network != _networkGeneration) {
        return SessionVerification.temporaryFailure;
      }
      if (refreshFirst) {
        final result = await _refreshOnce();
        if (result != SessionVerification.verified) return result;
      }
      final access = _api.accessToken;
      if (generation != _generation || access == null || access.isEmpty) {
        return SessionVerification.unverifiable;
      }
      final raw = await _api.get('/api/auth/session/',
          headers: {'Authorization': 'Bearer $access'},
          includeAuthHeader: false);
      if (generation != _generation) {
        return SessionVerification.identityMismatch;
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final user = map['user'] as Map<String, dynamic>;
      final settings = map['settings'] as Map<String, dynamic>;
      final id = user['id'];
      final verified = user['is_verified'];
      final biometric = settings['biometric_enabled'];
      if (id is! int || id <= 0 || verified is! bool || biometric is! bool) {
        return SessionVerification.unverifiable;
      }
      if (!verified || (expected != null && expected != id)) {
        await clearSession();
        return verified
            ? SessionVerification.identityMismatch
            : SessionVerification.definitiveRejection;
      }
      final anchor = await _readBootTime?.call();
      final authorization = anchor == null
          ? null
          : OfflineAuthorization(
              ownerId: id,
              biometricRequired: biometric,
              verifiedAt: DateTime.now().toUtc(),
              anchor: anchor,
            );
      await _writeSession(() async {
        if (generation == _generation && network == _networkGeneration) {
          await _storage.writeOfflineAuthorization(
            authorization == null ? null : jsonEncode(authorization.toJson()),
          );
        }
      });
      if (generation != _generation) {
        return SessionVerification.identityMismatch;
      }
      if (network != _networkGeneration) {
        return SessionVerification.temporaryFailure;
      }
      _ownerId = id;
      _biometricRequired = biometric;
      _remoteVerified = true;
      _offlineExpiry?.cancel();
      return SessionVerification.verified;
    } on ApiException catch (error) {
      if (generation != _generation) {
        return SessionVerification.identityMismatch;
      }
      final result = _classify(error, refreshing: false);
      if (result == SessionVerification.definitiveRejection) {
        await clearSession();
      }
      return result;
    } catch (_) {
      return SessionVerification.unverifiable;
    }
  }

  /// One refresh for concurrent authenticated requests.
  Future<bool> refreshFromStorage() async =>
      await _refreshOnce() == SessionVerification.verified;

  Future<SessionVerification> _refreshOnce() {
    final running = _refreshInFlight;
    if (running != null) return running;
    final generation = _generation;
    late final Future<SessionVerification> attempt;
    attempt = _refresh(generation).whenComplete(() {
      if (identical(_refreshInFlight, attempt)) _refreshInFlight = null;
    });
    return _refreshInFlight = attempt;
  }

  Future<SessionVerification> _refresh(int generation) async {
    var uncertain = false;
    try {
      final refresh = await _storage.readRefreshToken();
      if (generation != _generation) {
        return SessionVerification.identityMismatch;
      }
      if (refresh == null || refresh.isEmpty) {
        await clearSession();
        return SessionVerification.definitiveRejection;
      }
      if (usesAccountAuthorization) {
        uncertain = await _storage.readRefreshUncertain();
        await _writeSession(() async {
          if (generation == _generation) {
            await _storage.writeRefreshUncertain(true);
          }
        });
        if (generation != _generation) {
          return SessionVerification.identityMismatch;
        }
      }
      final raw = await _api.post(
        '/api/auth/token/refresh/',
        body: jsonEncode({'refresh': refresh}),
        includeAuthHeader: false,
      );
      if (generation != _generation) {
        return SessionVerification.identityMismatch;
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final access = map['access'] as String?;
      final newRefresh = map['refresh'] as String?;
      if (access == null || access.isEmpty) {
        return SessionVerification.unverifiable;
      }
      await _writeSession(() async {
        if (generation != _generation) return;
        if (newRefresh != null && newRefresh.isNotEmpty) {
          await _storage.writeRefreshToken(newRefresh);
        }
        if (usesAccountAuthorization) {
          await _storage.writeRefreshUncertain(false);
        }
      });
      if (generation != _generation) {
        return SessionVerification.identityMismatch;
      }
      _api.accessToken = access;
      return SessionVerification.verified;
    } on ApiException catch (error) {
      if (generation != _generation) {
        return SessionVerification.identityMismatch;
      }
      final result = _classify(error, refreshing: true);
      if (uncertain &&
          error.statusCode == 401 &&
          error.code == 'token_not_valid') {
        return SessionVerification.unverifiable;
      }
      if (usesAccountAuthorization &&
          result == SessionVerification.unverifiable) {
        await _writeSession(() async {
          if (generation == _generation) {
            await _storage.writeRefreshUncertain(uncertain);
          }
        });
      }
      if (result == SessionVerification.definitiveRejection) {
        await clearSession();
      }
      return result;
    } catch (_) {
      return SessionVerification.unverifiable;
    }
  }

  Future<void> login({required String email, required String password}) async {
    final cleared = clearSession(notify: false);
    final generation = _generation;
    await cleared;
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
    await _acceptLogin(generation, access, refresh);
  }

  Future<void> _acceptLogin(
      int generation, String access, String refresh) async {
    await _writeSession(() async {
      if (generation == _generation) await _storage.writeRefreshToken(refresh);
    });
    if (generation != _generation) throw ApiException('La sesión cambió');
    _api.accessToken = access;
    if (usesAccountAuthorization &&
        await verifySession(refreshFirst: false) !=
            SessionVerification.verified) {
      throw ApiException('No se pudo verificar la cuenta');
    }
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

  void _invalidateMemory() {
    _generation++;
    _refreshInFlight = null;
    _verificationInFlight = null;
    _offlineExpiry?.cancel();
    _ownerId = null;
    _biometricRequired = false;
    localDataUnlocked = false;
    offlineDeviceUnlockAvailable = true;
    _remoteVerified = false;
    _api.accessToken = null;
  }

  Future<void> clearSession({bool notify = true}) {
    _invalidateMemory();
    final cleared = _writeSession(() async {
      await _storage.writeOfflineAuthorization(null);
      await _storage.writeRefreshToken(null);
      await _storage.writeRefreshUncertain(false);
    });
    if (notify) onSessionInvalid?.call();
    return cleared;
  }

  Future<void> logout() async {
    var access = _api.accessToken;
    final refresh = _storage.readRefreshToken().catchError((Object _) => null);
    final clearing = clearSession();
    final generation = _generation;
    await clearing;
    try {
      var token = await refresh;
      if (token == null || token.isEmpty || generation != _generation) return;
      if (access == null || access.isEmpty) {
        final raw = await _api.post(
          '/api/auth/token/refresh/',
          body: jsonEncode({'refresh': token}),
          includeAuthHeader: false,
        );
        final credentials = jsonDecode(raw) as Map<String, dynamic>;
        access = credentials['access'] as String?;
        token = credentials['refresh'] as String? ?? token;
      }
      if (access == null || access.isEmpty || generation != _generation) return;
      await _api.post(
        '/api/auth/logout/',
        body: jsonEncode({'refresh': token}),
        headers: {'Authorization': 'Bearer $access'},
        includeAuthHeader: false,
      );
    } catch (_) {
      // Local invalidation has already completed.
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
    final generation = _generation;
    await _api.put(
      '/api/users/biometric-status/',
      body: jsonEncode({'biometric_enabled': enabled}),
      headers: {'Accept': 'application/json'},
    );
    if (!usesAccountAuthorization || generation != _generation) return;
    _biometricRequired = enabled;
    await _writeSession(() async {
      if (generation != _generation) return;
      final previous = await _storedAuthorization();
      if (previous == null || previous.ownerId != _ownerId) return;
      await _storage.writeOfflineAuthorization(jsonEncode(
        OfflineAuthorization(
          ownerId: previous.ownerId,
          biometricRequired: enabled,
          verifiedAt: previous.verifiedAt,
          anchor: previous.anchor,
        ).toJson(),
      ));
    });
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
    final cleared = clearSession(notify: false);
    final generation = _generation;
    await cleared;
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
    await _acceptLogin(generation, access, refresh);
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
