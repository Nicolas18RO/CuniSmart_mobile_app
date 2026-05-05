import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../errors/api_exception.dart';

/// Thin HTTP client: base URL + verbs. [accessToken] is in-memory only (never persisted).
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _client = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

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
  }) async {
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
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.body.isNotEmpty ? response.body : 'Request failed',
        statusCode: response.statusCode,
      );
    }
    return response.body;
  }

  Future<String> post(
    String path, {
    required String body,
    Map<String, String> headers = const {},
    bool includeAuthHeader = true,
  }) async {
    final mergedBase = _mergeHeaders(
      {...headers, 'Content-Type': 'application/json'},
      includeAuthHeader: includeAuthHeader,
    );
    var response = await _client.post(
      _uri(path),
      headers: mergedBase,
      body: body,
    );
    if (response.statusCode == 401 &&
        includeAuthHeader &&
        onTokenRefresh != null) {
      final refreshed = await onTokenRefresh!();
      if (refreshed) {
        final retryHeaders = _mergeHeaders(
          {...headers, 'Content-Type': 'application/json'},
          includeAuthHeader: includeAuthHeader,
        );
        response = await _client.post(
          _uri(path),
          headers: retryHeaders,
          body: body,
        );
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.body.isNotEmpty ? response.body : 'Request failed',
        statusCode: response.statusCode,
      );
    }
    return response.body;
  }

  Future<String> put(
    String path, {
    required String body,
    Map<String, String> headers = const {},
    bool includeAuthHeader = true,
  }) async {
    final mergedBase = _mergeHeaders(
      {...headers, 'Content-Type': 'application/json'},
      includeAuthHeader: includeAuthHeader,
    );
    var response = await _client.put(
      _uri(path),
      headers: mergedBase,
      body: body,
    );
    if (response.statusCode == 401 &&
        includeAuthHeader &&
        onTokenRefresh != null) {
      final refreshed = await onTokenRefresh!();
      if (refreshed) {
        final retryHeaders = _mergeHeaders(
          {...headers, 'Content-Type': 'application/json'},
          includeAuthHeader: includeAuthHeader,
        );
        response = await _client.put(
          _uri(path),
          headers: retryHeaders,
          body: body,
        );
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.body.isNotEmpty ? response.body : 'Request failed',
        statusCode: response.statusCode,
      );
    }
    return response.body;
  }

  Future<String> delete(
    String path, {
    Map<String, String> headers = const {},
    bool includeAuthHeader = true,
  }) async {
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
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.body.isNotEmpty ? response.body : 'Request failed',
        statusCode: response.statusCode,
      );
    }
    return response.body;
  }

  void close() => _client.close();
}
