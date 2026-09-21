import 'dart:convert';

/// HTTP / API failure from [ApiClient] or services.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, String? code}) : _code = code;

  final String message;
  final int? statusCode;
  final String? _code;

  /// Explicit [code] or backend `{ "code": "..." }` when the body is JSON.
  String? get code {
    if (_code != null && _code.isNotEmpty) return _code;
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map && decoded['code'] != null) {
        return decoded['code'].toString();
      }
    } catch (_) {}
    return null;
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
