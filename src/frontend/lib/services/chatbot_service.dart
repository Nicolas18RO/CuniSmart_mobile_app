import 'dart:convert';

import '../core/errors/api_exception.dart';
import '../core/network/api_client.dart';

class ChatbotService {
  ChatbotService(this._client);

  final ApiClient _client;

  static const String _path = '/api/chatbot/';

  Future<String> sendMessage({
    required String message,
    required List<Map<String, dynamic>> history,
  }) async {
    try {
      final raw = await _client.post(
        _path,
        body: jsonEncode({'message': message, 'history': history}),
        headers: {'Accept': 'application/json'},
        includeAuthHeader: false,
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final response = decoded['response'];
      if (response is! String) {
        throw ApiException('Respuesta inválida del asistente', statusCode: 200);
      }
      return response;
    } on ApiException {
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(
        ApiException('Network or parse error: $e'),
        st,
      );
    }
  }
}

