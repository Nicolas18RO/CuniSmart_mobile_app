import 'dart:async';

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

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> _mergeHeaders(
    Map<String, String> headers, {
    required bool includeAuthHeader,
  }) {
    final h = Map<String, String>.from(headers);
    h.putIfAbsent('Accept', () => 'application/json');
    if (includeAuthHeader &&
        accessToken != null &&
        accessToken!.isNotEmpty) {
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
  }) {
    return _guard(() async {
      var response = await _getOnce(
        path,
        headers: headers,
        includeAuthHeader: includeAuthHeader,
      );
      if (response.statusCode == 401 &&
          includeAuthHeader &&
          onTokenRefresh != null) {
        final refreshed = await onTokenRefresh!();
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

    return _guard(() async {
      var response = await send();
      if (response.statusCode == 401 &&
          includeAuthHeader &&
          onTokenRefresh != null) {
        final refreshed = await onTokenRefresh!();
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

    return _guard(() async {
      var response = await send();
      if (response.statusCode == 401 &&
          includeAuthHeader &&
          onTokenRefresh != null) {
        final refreshed = await onTokenRefresh!();
        if (refreshed) {
          response = await send();
        }
      }
      return _bodyOrThrow(response);
    });
  }

  Future<String> delete(
    String path, {
    Map<String, String> headers = const {},
    bool includeAuthHeader = true,
  }) {
    return _guard(() async {
      var response = await _client.delete(
        _uri(path),
        headers: _mergeHeaders(headers, includeAuthHeader: includeAuthHeader),
      );
      if (response.statusCode == 401 &&
          includeAuthHeader &&
          onTokenRefresh != null) {
        final refreshed = await onTokenRefresh!();
        if (refreshed) {
          response = await _client.delete(
            _uri(path),
            headers: _mergeHeaders(headers, includeAuthHeader: includeAuthHeader),
          );
        }
      }
      return _bodyOrThrow(response);
    });
  }

  Future<String> _guard(Future<String> Function() send) async {
    try {
      return await send().timeout(_timeout);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('Request timed out', code: 'network');
    } catch (e) {
      if (e is http.ClientException || _isSocketLike(e)) {
        throw ApiException('Network error', code: 'network');
      }
      rethrow;
    }
  }

  String _bodyOrThrow(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.body.isNotEmpty ? response.body : 'Request failed',
        statusCode: response.statusCode,
      );
    }
    return response.body;
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
