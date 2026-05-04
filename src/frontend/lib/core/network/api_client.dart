import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../errors/api_exception.dart';

/// Thin HTTP client: base URL + GET/POST. No domain logic.
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _client = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<String> get(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _client.get(
      _uri(path),
      headers: headers,
    );
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
  }) async {
    final response = await _client.post(
      _uri(path),
      headers: headers,
      body: body,
    );
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
