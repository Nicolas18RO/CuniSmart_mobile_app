import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../errors/api_exception.dart';

/// Thin HTTP client: base URL + verbs. [accessToken] is in-memory only (never persisted).
class ApiClient {
  ApiClient({
    http.Client? httpClient,
    String? baseUrl,
    Duration? timeout,
  })  : _client = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _timeout = timeout ?? const Duration(seconds: 20);

  final http.Client _client;
  final String _baseUrl;
  final Duration _timeout;

  /// Short-lived JWT; set by [AuthService] after login or refresh. Not stored on disk.
  String? accessToken;

  /// If set, invoked on 401 to refresh access; should return true if a new [accessToken] was set.
  Future<bool> Function()? onTokenRefresh;
  int Function()? sessionGeneration;
  void Function()? onBackendUnavailable;

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> _mergeHeaders(
    Map<String, String> headers, {
    required bool includeAuthHeader,
  }) {
    final h = Map<String, String>.from(headers);
    h.putIfAbsent('Accept', () => 'application/json');
    if (includeAuthHeader && accessToken != null && accessToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $accessToken';
    }
    return h;
  }

  Future<http.Response> _getOnce(
    String path, {
    required Map<String, String> headers,
    required bool includeAuthHeader,
  }) {
    return _client.get(
      _uri(path),
      headers: _mergeHeaders(headers, includeAuthHeader: includeAuthHeader),
    );
  }

  Future<String> get(
    String path, {
    Map<String, String> headers = const {},
    bool includeAuthHeader = true,
    bool retryOnUnauthorized = true,
  }) {
    return _guard((checkSession) async {
      var response = await _getOnce(
        path,
        headers: headers,
        includeAuthHeader: includeAuthHeader,
      );
      checkSession();
      if (response.statusCode == 401 &&
          includeAuthHeader &&
          retryOnUnauthorized &&
          onTokenRefresh != null) {
        final refreshed = await onTokenRefresh!();
        checkSession();
        if (refreshed) {
          response = await _getOnce(
            path,
            headers: headers,
            includeAuthHeader: includeAuthHeader,
          );
        }
      }
      return _bodyOrThrow(response);
    });
  }

  Future<String> post(
    String path, {
    required String body,
    Map<String, String> headers = const {},
    bool includeAuthHeader = true,
    bool retryOnUnauthorized = true,
  }) {
    Future<http.Response> send() {
      return _client.post(
        _uri(path),
        headers: _mergeHeaders(
          {...headers, 'Content-Type': 'application/json'},
          includeAuthHeader: includeAuthHeader,
        ),
        body: body,
      );
    }

    return _guard((checkSession) async {
      var response = await send();
      checkSession();
      if (response.statusCode == 401 &&
          includeAuthHeader &&
          retryOnUnauthorized &&
          onTokenRefresh != null) {
        final refreshed = await onTokenRefresh!();
        checkSession();
        if (refreshed) {
          response = await send();
        }
      }
      return _bodyOrThrow(response);
    });
  }

  Future<String> put(
    String path, {
    required String body,
    Map<String, String> headers = const {},
    bool includeAuthHeader = true,
    bool retryOnUnauthorized = true,
  }) {
    Future<http.Response> send() {
      return _client.put(
        _uri(path),
        headers: _mergeHeaders(
          {...headers, 'Content-Type': 'application/json'},
          includeAuthHeader: includeAuthHeader,
        ),
        body: body,
      );
    }

    return _guard((checkSession) async {
      var response = await send();
      checkSession();
      if (response.statusCode == 401 &&
          includeAuthHeader &&
          retryOnUnauthorized &&
          onTokenRefresh != null) {
        final refreshed = await onTokenRefresh!();
        checkSession();
        if (refreshed) {
          response = await send();
        }
      }
      return _bodyOrThrow(response);
    });
  }

  Future<String> patch(
    String path, {
    required String body,
    Map<String, String> headers = const {},
    bool includeAuthHeader = true,
    bool retryOnUnauthorized = true,
  }) {
    Future<http.Response> send() => _client.patch(
          _uri(path),
          headers: _mergeHeaders(
            {...headers, 'Content-Type': 'application/json'},
            includeAuthHeader: includeAuthHeader,
          ),
          body: body,
        );
    return _guard((checkSession) async {
      var response = await send();
      checkSession();
      if (response.statusCode == 401 &&
          includeAuthHeader &&
          retryOnUnauthorized &&
          onTokenRefresh != null) {
        final refreshed = await onTokenRefresh!();
        checkSession();
        if (refreshed) response = await send();
      }
      return _bodyOrThrow(response);
    });
  }

  Future<String> delete(
    String path, {
    String? body,
    Map<String, String> headers = const {},
    bool includeAuthHeader = true,
    bool retryOnUnauthorized = true,
  }) {
    return _guard((checkSession) async {
      Future<http.Response> send() => _client.delete(
            _uri(path),
            headers: _mergeHeaders(
              body == null
                  ? headers
                  : {...headers, 'Content-Type': 'application/json'},
              includeAuthHeader: includeAuthHeader,
            ),
            body: body,
          );
      var response = await send();
      checkSession();
      if (response.statusCode == 401 &&
          includeAuthHeader &&
          retryOnUnauthorized &&
          onTokenRefresh != null) {
        final refreshed = await onTokenRefresh!();
        checkSession();
        if (refreshed) {
          response = await send();
        }
      }
      return _bodyOrThrow(response);
    });
  }

  Future<http.Response> sendSyncCommand(
    String method,
    String path,
    String body,
    Map<String, String> headers,
  ) =>
      _guard((check) async {
        check();
        final request = http.Request(method, _uri(path))
          ..followRedirects = false
          ..headers.addAll(_mergeHeaders(headers, includeAuthHeader: true))
          ..body = body;
        return http.Response.fromStream(await _client.send(request));
      });

  Future<T> _guard<T>(Future<T> Function(void Function()) send) async {
    final generation = sessionGeneration?.call();
    var active = true;
    void checkSession() {
      if (!active || generation != sessionGeneration?.call()) {
        throw ApiException('La sesión cambió', code: 'session_changed');
      }
    }

    void unavailable() {
      if (generation == sessionGeneration?.call()) onBackendUnavailable?.call();
    }

    try {
      final result = await send(checkSession).timeout(_timeout);
      checkSession();
      return result;
    } on ApiException catch (error) {
      if (error.code == 'network' || (error.statusCode ?? 0) >= 500) {
        unavailable();
      }
      rethrow;
    } on TimeoutException {
      unavailable();
      throw ApiException('Request timed out', code: 'network');
    } catch (e) {
      if (e is http.ClientException || _isSocketLike(e)) {
        unavailable();
        throw ApiException('Network error', code: 'network');
      }
      rethrow;
    } finally {
      active = false;
    }
  }

  String _bodyOrThrow(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final rawBody = response.body;

      final parsed = _safeError(response);
      throw ApiException(
        parsed.message,
        statusCode: response.statusCode,
        code: parsed.code,
        rawBody: rawBody.isEmpty ? null : rawBody,
      );
    }
    return response.body;
  }

  ({String message, String? code}) _safeError(http.Response response) {
    final status = response.statusCode;
    final raw = response.body.trim();
    String? code;
    String? detail;

    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final looksLikeHtml = contentType.contains('text/html') ||
        raw.startsWith('<!DOCTYPE html') ||
        raw.startsWith('<html');

    if (!looksLikeHtml && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          code = decoded['code']?.toString();
          for (final key in const ['detail', 'message', 'error']) {
            final value = decoded[key];
            if (value is String && value.trim().isNotEmpty) {
              detail = value.trim();
              break;
            }
          }
        }
      } catch (_) {
        // Plain-text and HTML server responses are intentionally not exposed.
      }
    }

    if (status >= 500) {
      return (
        message: 'Ocurrió un problema en el servidor. Intenta nuevamente.',
        code: code ?? 'server_error',
      );
    }

    if (detail != null) {
      final safeDetail =
          detail.length > 300 ? '${detail.substring(0, 300)}…' : detail;
      return (message: safeDetail, code: code);
    }

    final message = switch (status) {
      400 =>
        'La solicitud no es válida. Revisa la información e intenta nuevamente.',
      401 => 'Tu sesión venció. Inicia sesión nuevamente.',
      403 => 'No tienes permiso para realizar esta acción.',
      404 => 'No se encontró la información solicitada.',
      _ => 'No se pudo completar la solicitud. Intenta nuevamente.',
    };
    return (message: message, code: code);
  }

  static bool _isSocketLike(Object error) {
    switch (error.runtimeType.toString()) {
      case 'SocketException':
      case 'HandshakeException':
      case 'TlsException':
      case 'HttpException':
        return true;
    }
    return false;
  }

  void close() => _client.close();
}
