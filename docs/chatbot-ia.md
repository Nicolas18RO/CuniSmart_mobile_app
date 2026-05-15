# 🐇 CuniSmart — Plan de Implementación: Chatbot con Google AI Studio (Gemini)

> **Rol:** Experto en implementación de chatbots con IA  
> **Stack:** Flutter (frontend) + Django REST Framework (backend)  
> **API:** Google AI Studio — Gemini  
> **Arquitectura:** Clean Architecture + buenas prácticas  
> **Timeline estimado:** 5–8 días

---

## 📁 Estructura del Proyecto

```
cunismart/
├── backend/                         # Django REST Framework
│   ├── cunismart_backend/
│   │   ├── settings.py
│   │   └── urls.py
│   ├── chatbot/                     # App dedicada al chatbot
│   │   ├── __init__.py
│   │   ├── models.py                # Historial de conversaciones
│   │   ├── serializers.py
│   │   ├── views.py                 # Endpoint del chatbot
│   │   ├── urls.py
│   │   └── services/
│   │       └── gemini_service.py    # Lógica de integración con Gemini
│   ├── .env                         # Variables de entorno (NO versionar)
│   ├── .env.example                 # Plantilla pública
│   └── requirements.txt
│
└── frontend/                        # Flutter
    ├── lib/
    │   ├── features/
    │   │   └── chatbot/
    │   │       ├── data/
    │   │       │   └── chatbot_repository.dart
    │   │       ├── domain/
    │   │       │   └── chatbot_usecase.dart
    │   │       └── presentation/
    │   │           ├── chatbot_screen.dart
    │   │           └── chatbot_provider.dart
    │   └── core/
    │       └── services/
    │           └── api_service.dart
    └── .env                         # Variables Flutter (NO versionar)
```

---

## 🔐 Paso 0 — Configuración del `.env`

### `backend/.env`
```env
# Google AI Studio - Gemini
GEMINI_API_KEY=your_gemini_api_key_here

# Django
SECRET_KEY=your_django_secret_key
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1

# Database (opcional para MVP)
DATABASE_URL=sqlite:///db.sqlite3
```

### `backend/.env.example` (versionar esto, NO el .env)
```env
GEMINI_API_KEY=
SECRET_KEY=
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1
DATABASE_URL=sqlite:///db.sqlite3
```

### `.gitignore` — asegúrate de incluir:
```
.env
*.pyc
__pycache__/
```

---

## ⚙️ Paso 1 — Backend: Configuración Django

### 1.1 Instalar dependencias

```bash
pip install django djangorestframework python-dotenv google-generativeai
pip freeze > requirements.txt
```

### 1.2 `settings.py` — cargar `.env`

```python
# settings.py
from pathlib import Path
import os
from dotenv import load_dotenv

load_dotenv()

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

INSTALLED_APPS = [
    ...
    'rest_framework',
    'chatbot',
]
```

### 1.3 Crear app del chatbot

```bash
python manage.py startapp chatbot
```

---

## 🤖 Paso 2 — Backend: Servicio Gemini

### `chatbot/services/gemini_service.py`

```python
import google.generativeai as genai
from django.conf import settings

# Configuración única al cargar el módulo
genai.configure(api_key=settings.GEMINI_API_KEY)

SYSTEM_PROMPT = """
Eres CuniBot, un asistente inteligente especializado en cunicultura (cría de conejos).
Ayudas a agricultores rurales a:
- Gestionar el registro de sus animales
- Interpretar datos de sensores IoT (temperatura, peso, agua)
- Recibir alertas y recomendaciones sobre su granja
- Responder preguntas sobre salud y producción de conejos

Responde siempre de forma clara, concisa y accesible.
Si el usuario tiene discapacidad visual, prioriza respuestas cortas y precisas.
Idioma: español.
"""

def get_gemini_response(user_message: str, history: list = None) -> str:
    """
    Envía un mensaje al modelo Gemini y retorna la respuesta.
    
    Args:
        user_message: Mensaje del usuario
        history: Lista de mensajes previos [{"role": "user/model", "parts": ["texto"]}]
    
    Returns:
        Respuesta del modelo como string
    """
    model = genai.GenerativeModel(
        model_name="gemini-1.5-flash",
        system_instruction=SYSTEM_PROMPT,
    )

    chat = model.start_chat(history=history or [])
    response = chat.send_message(user_message)

    return response.text
```

> **Nota:** `gemini-1.5-flash` es el modelo recomendado — rápido, gratuito en tier básico y eficiente para casos de uso conversacional.

---

## 📡 Paso 3 — Backend: API Endpoint

### `chatbot/serializers.py`

```python
from rest_framework import serializers

class ChatMessageSerializer(serializers.Serializer):
    message = serializers.CharField(max_length=1000)
    history = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        default=list
    )
```

### `chatbot/views.py`

```python
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from .serializers import ChatMessageSerializer
from .services.gemini_service import get_gemini_response

class ChatbotView(APIView):
    """
    POST /api/chatbot/
    Recibe un mensaje y retorna la respuesta del asistente IA.
    """

    def post(self, request):
        serializer = ChatMessageSerializer(data=request.data)

        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        user_message = serializer.validated_data["message"]
        history = serializer.validated_data.get("history", [])

        try:
            ai_response = get_gemini_response(user_message, history)
            return Response({"response": ai_response}, status=status.HTTP_200_OK)

        except Exception as e:
            return Response(
                {"error": "No se pudo conectar con el asistente IA."},
                status=status.HTTP_503_SERVICE_UNAVAILABLE
            )
```

### `chatbot/urls.py`

```python
from django.urls import path
from .views import ChatbotView

urlpatterns = [
    path("chatbot/", ChatbotView.as_view(), name="chatbot"),
]
```

### `cunismart_backend/urls.py`

```python
from django.urls import path, include

urlpatterns = [
    path("api/", include("chatbot.urls")),
]
```

---

## 📱 Paso 4 — Flutter: Arquitectura del Chatbot

### 4.1 Dependencias — `pubspec.yaml`

```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
  provider: ^6.1.2
  flutter_dotenv: ^5.1.0  # Para variables de entorno en Flutter
```

### 4.2 `.env` en Flutter (raíz del proyecto)

```env
API_BASE_URL=http://127.0.0.1:8000/api
```

Registrar en `pubspec.yaml`:
```yaml
flutter:
  assets:
    - .env
```

### 4.3 `lib/features/chatbot/data/chatbot_repository.dart`

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ChatbotRepository {
  final String _baseUrl = dotenv.env['API_BASE_URL'] ?? '';

  Future<String> sendMessage(String message, List<Map<String, dynamic>> history) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/chatbot/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': message, 'history': history}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['response'] as String;
    } else {
      throw Exception('Error al contactar al asistente');
    }
  }
}
```

### 4.4 `lib/features/chatbot/domain/chatbot_usecase.dart`

```dart
import '../data/chatbot_repository.dart';

class SendChatMessageUseCase {
  final ChatbotRepository _repository;

  SendChatMessageUseCase(this._repository);

  Future<String> execute(String message, List<Map<String, dynamic>> history) {
    return _repository.sendMessage(message, history);
  }
}
```

### 4.5 `lib/features/chatbot/presentation/chatbot_provider.dart`

```dart
import 'package:flutter/material.dart';
import '../domain/chatbot_usecase.dart';

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class ChatbotProvider extends ChangeNotifier {
  final SendChatMessageUseCase _useCase;

  ChatbotProvider(this._useCase);

  final List<ChatMessage> messages = [];
  bool isLoading = false;

  List<Map<String, dynamic>> get _geminiHistory => messages
      .map((m) => {
            'role': m.isUser ? 'user' : 'model',
            'parts': [m.text],
          })
      .toList();

  Future<void> sendMessage(String text) async {
    messages.add(ChatMessage(text: text, isUser: true));
    isLoading = true;
    notifyListeners();

    try {
      final response = await _useCase.execute(text, _geminiHistory);
      messages.add(ChatMessage(text: response, isUser: false));
    } catch (_) {
      messages.add(ChatMessage(
        text: 'Error al conectar con el asistente. Verifica tu conexión.',
        isUser: false,
      ));
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
```

### 4.6 `lib/features/chatbot/presentation/chatbot_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'chatbot_provider.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _sendMessage(ChatbotProvider provider) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    provider.sendMessage(text).then((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatbotProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('CuniBot 🐇'),
        semanticLabel: 'Asistente de granja CuniBot',
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: provider.messages.length,
              itemBuilder: (_, i) {
                final msg = provider.messages[i];
                return Semantics(
                  label: msg.isUser ? 'Tú dijiste: ${msg.text}' : 'CuniBot dijo: ${msg.text}',
                  child: _MessageBubble(message: msg),
                );
              },
            ),
          ),
          if (provider.isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(semanticsLabel: 'CuniBot está respondiendo'),
            ),
          _InputBar(controller: _controller, onSend: () => _sendMessage(provider)),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: message.isUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _InputBar({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Pregúntale a CuniBot...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => onSend(),
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Enviar mensaje',
            child: IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send),
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## 🔗 Paso 5 — Registro de dependencias en Flutter

### `lib/main.dart` — inicializar dotenv y providers

```dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'features/chatbot/data/chatbot_repository.dart';
import 'features/chatbot/domain/chatbot_usecase.dart';
import 'features/chatbot/presentation/chatbot_provider.dart';
import 'features/chatbot/presentation/chatbot_screen.dart';

Future<void> main() async {
  await dotenv.load(fileName: '.env');
  runApp(const CuniSmartApp());
}

class CuniSmartApp extends StatelessWidget {
  const CuniSmartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatbotProvider(
            SendChatMessageUseCase(ChatbotRepository()),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'CuniSmart',
        home: const ChatbotScreen(),
      ),
    );
  }
}
```

---

## ✅ Checklist de Implementación

### Backend
- [ ] Crear app `chatbot` en Django
- [ ] Instalar dependencias: `google-generativeai`, `python-dotenv`
- [ ] Configurar `.env` con `GEMINI_API_KEY`
- [ ] Implementar `gemini_service.py` con system prompt de cunicultura
- [ ] Crear endpoint `POST /api/chatbot/`
- [ ] Agregar URL en `urls.py` principal
- [ ] Probar con `curl` o Postman

### Flutter
- [ ] Agregar dependencias en `pubspec.yaml`
- [ ] Crear `.env` con `API_BASE_URL`
- [ ] Registrar `.env` en assets
- [ ] Implementar `ChatbotRepository`
- [ ] Implementar `SendChatMessageUseCase`
- [ ] Implementar `ChatbotProvider` con historial de mensajes
- [ ] Crear `ChatbotScreen` con soporte de accesibilidad (Semantics)
- [ ] Registrar provider en `main.dart`

---

## 🧪 Paso 6 — Prueba rápida del backend

```bash
curl -X POST http://127.0.0.1:8000/api/chatbot/ \
  -H "Content-Type: application/json" \
  -d '{"message": "¿Cuántos litros de agua necesita un conejo al día?"}'
```

Respuesta esperada:
```json
{
  "response": "Un conejo adulto necesita aproximadamente 100-600 ml de agua al día, dependiendo de su tamaño y dieta..."
}
```

---

## 📋 Reglas Aplicadas

| Regla | Cómo se aplicó |
|---|---|
| ✅ Buenas prácticas | Clean Architecture: data → domain → presentation |
| ✅ Sin código innecesario | Cada archivo tiene una única responsabilidad |
| ✅ Arquitectura limpia | Separación por capas, `UseCase` como intermediario, `Repository` aislado |
| ✅ Seguridad | API Key solo en `.env`, nunca en código fuente |
| ✅ Accesibilidad | Widgets con `Semantics` para lectores de pantalla |

---

## 🗓 Timeline Sugerido

| Día | Tarea |
|-----|-------|
| 1 | Configurar `.env`, instalar dependencias backend |
| 2 | Implementar `gemini_service.py` + endpoint Django |
| 3 | Probar API con Postman, ajustar system prompt |
| 4 | Implementar Repository + UseCase en Flutter |
| 5 | Implementar Provider + ChatbotScreen |
| 6 | Integrar en navegación principal de la app |
| 7–8 | Testing con usuarios + ajustes de accesibilidad |

---

*Plan generado: Mayo 2026 — CuniSmart MVP*