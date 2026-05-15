import 'package:flutter/foundation.dart';

import '../core/errors/api_exception.dart';
import '../services/chatbot_service.dart';

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class ChatbotViewModel extends ChangeNotifier {
  ChatbotViewModel(this._service);

  final ChatbotService _service;

  final List<ChatMessage> messages = [];
  bool isLoading = false;

  String _formatError(Object error) {
    if (error is ApiException) {
      final code = error.statusCode;
      if (code != null) {
        return 'Error ($code): ${error.message}';
      }
      return error.message;
    }
    return error.toString();
  }

  List<Map<String, dynamic>> _toGeminiHistory(List<ChatMessage> msgs) {
    return msgs
        .map(
          (m) => {
            'role': m.isUser ? 'user' : 'model',
            'parts': [m.text],
          },
        )
        .toList();
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (isLoading) return;

    // History BEFORE adding the new user message (server adds current message separately).
    final history = _toGeminiHistory(List<ChatMessage>.from(messages));

    messages.add(ChatMessage(text: trimmed, isUser: true));
    isLoading = true;
    notifyListeners();

    try {
      final response = await _service.sendMessage(
        message: trimmed,
        history: history,
      );
      messages.add(ChatMessage(text: response, isUser: false));
    } catch (e) {
      messages.add(
        ChatMessage(
          text:
              'No pude responder en este momento. Revisa tu conexión y vuelve a intentar.\n\nDetalle: ${_formatError(e)}',
          isUser: false,
        ),
      );
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void clearChat() {
    if (isLoading) return;
    messages.clear();
    notifyListeners();
  }
}

