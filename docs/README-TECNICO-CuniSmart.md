# CuniSmart — README técnico

Documentación técnica del **MVP CuniSmart**: aplicación móvil para cunicultura con registro de animales, sensores IoT, alertas accesibles y asistente de chat (CuniBot) integrado con la API de Gemini vía backend Django.

Este documento describe **arquitectura, estructura del repositorio, configuración, APIs y comandos** para desarrollo y depuración.

---

## 1. Visión general del sistema

| Capa | Tecnología | Ubicación en el repo |
|------|------------|----------------------|
| Cliente móvil | Flutter (Dart) | `src/frontend/` |
| API REST | Django + Django REST Framework | `src/backend/` |
| Base de datos | PostgreSQL (configurable por variables de entorno) | — |
| Autenticación | JWT (Simple JWT), refresh en almacenamiento seguro en el cliente | `accounts`, `ApiClient` |
| Chat IA | Google Gen AI SDK (`google-genai`) en el servidor | `chatbot` |

**Flujo típico:** la app Flutter usa `ApiClient` con una URL base (`AppConfig.apiBaseUrl`) y rutas bajo `/api/...`. El chatbot llama a `POST /api/chatbot/` sin JWT obligatorio en esa vista (configuración explícita en el backend).

---

## 2. Estructura del repositorio

```
CuniSmart_mobile_app/
├── AGENTS.md                 # Reglas y convenciones del proyecto para agentes/humanos
├── docs/                     # Documentación de producto y técnica
│   └── README-TECNICO-CuniSmart.md   # Este archivo
├── src/
│   ├── backend/              # Django (manage.py aquí)
│   │   ├── venv/             # Entorno virtual Python (no duplicar)
│   │   ├── cunismart_backend/   # Proyecto Django (settings, urls, wsgi)
│   │   ├── accounts/         # Usuarios, auth JWT, verificación email
│   │   ├── core/             # API núcleo: conejos, lecturas de sensores (ViewSets)
│   │   ├── chatbot/          # Endpoint CuniBot + servicio Gemini
│   │   ├── .env              # Secretos locales (NO versionar; ver .gitignore)
│   │   └── .env.example      # Plantilla de variables
│   └── frontend/             # Proyecto Flutter
│       ├── lib/
│       │   ├── core/         # Config, red, tema, errores, voz
│       │   ├── models/
│       │   ├── services/     # HTTP: auth, rabbits, sensors, chatbot
│       │   ├── viewmodels/
│       │   └── views/
│       └── pubspec.yaml
```

**Reglas de layout (obligatorias en este repo):**

- No crear otro proyecto Django fuera de `src/backend/`.
- No crear otro proyecto Flutter fuera de `src/frontend/`.
- Reutilizar el `venv` existente en `src/backend/venv/` si ya existe.

---

## 3. Requisitos previos

### Herramientas

- **Python** 3.10+ (compatible con Django 5.x del proyecto).
- **Node no es obligatorio** para el MVP actual (solo Flutter + Django).
- **Flutter** SDK acorde a `pubspec.yaml` (`environment.sdk: ^3.5.4`).
- **PostgreSQL** accesible si usas la configuración por defecto de `settings.py` (motor `postgresql`).

### Cuentas / claves (solo desarrollo)

- **Google AI Studio / Gemini:** API key para `GEMINI_API_KEY` en `src/backend/.env`.
- **SMTP** (opcional): si pruebas registro/verificación por email, revisar variables `EMAIL_*` en `settings.py` y preferiblemente mover secretos a entorno (no versionar contraseñas).

---

## 4. Backend (Django REST)

### 4.1 Entorno virtual e instalación

```powershell
cd src\backend
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Si aparece `ModuleNotFoundError: No module named 'dotenv'`, el `venv` no tiene instaladas las dependencias actuales: ejecutar de nuevo `pip install -r requirements.txt` **con el venv activado**.

### 4.2 Variables de entorno

Crear `src/backend/.env` (no está en git). Referencia: `src/backend/.env.example`.

Variables relevantes (no exhaustivo; ver `cunismart_backend/settings.py`):

| Variable | Uso |
|----------|-----|
| `GEMINI_API_KEY` | Clave para el SDK de Gemini en el chatbot |
| `POSTGRES_*` | Conexión a PostgreSQL (`POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POSTGRES_PORT`) |
| `DJANGO_EMAIL_BACKEND`, `EMAIL_*`, `VERIFICATION_PUBLIC_BASE_URL`, etc. | Email y enlaces de verificación |

`settings.py` carga `.env` con `python-dotenv` desde el directorio `BASE_DIR` del backend (`load_dotenv(BASE_DIR / ".env")`).

### 4.3 Ejecución

```powershell
cd src\backend
.\venv\Scripts\Activate.ps1
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

- `127.0.0.1:8000` — mismo equipo.
- `0.0.0.0:8000` — acepta conexiones desde la LAN (útil para probar el teléfono físico).

### 4.4 Apps Django

| App | Responsabilidad |
|-----|-----------------|
| `cunismart_backend` | `settings`, `urls`, WSGI, configuración DRF/JWT |
| `accounts` | Modelo de usuario, registro, login, refresh, verificación email |
| `core` | Recursos MVP: conejos (`RabbitViewSet`), lecturas de sensores (`SensorReadingViewSet`) |
| `chatbot` | `POST /api/chatbot/` — mensaje + historial opcional → respuesta del modelo |

### 4.5 Rutas API principales

Prefijo base del servidor: `http://<host>:8000`.

| Ruta | Método | Notas |
|------|--------|--------|
| `/admin/` | GET | Panel Django |
| `/api/auth/...` | varios | Registro, login, bootstrap, refresh, verificación, etc. |
| `/api/users/...` | varios | Perfiles / usuarios (según `accounts.user_urls`) |
| `/api/rabbits/` | GET, POST | Lista y creación (router DRF) |
| `/api/rabbits/<id>/` | GET, PUT, PATCH, DELETE | Detalle y actualización |
| `/api/sensor-readings/` | GET | Lecturas IoT |
| `/api/chatbot/` | **POST** | Cuerpo JSON: `message` (string), `history` (lista opcional de `{role, parts}`) |

**Importante:** `GET /api/chatbot/` devuelve **405 Method Not Allowed** (solo está implementado `POST`).

Ejemplo de prueba:

```powershell
curl.exe -X POST "http://127.0.0.1:8000/api/chatbot/" ^
  -H "Content-Type: application/json" ^
  -d "{\"message\":\"Hola\",\"history\":[]}"
```

### 4.6 Chatbot y Gemini

- Implementación en `chatbot/services/gemini_service.py` usando el paquete **`google-genai`** (SDK actual recomendado por Google frente al paquete legacy `google-generativeai`).
- Si `GEMINI_API_KEY` falta o la llamada falla, la vista puede responder **503** y registrar el error en logs (según versión de `chatbot/views.py`).

### 4.7 Autenticación DRF

`REST_FRAMEWORK` usa por defecto `JWTAuthentication` y permisos configurados en `settings.py`. El endpoint del chatbot puede estar excluido de auth en la vista (`authentication_classes` / `permission_classes` vacíos) para simplificar pruebas; revisar `chatbot/views.py` antes de producción.

### 4.8 Pruebas backend

```powershell
cd src\backend
python manage.py test
python manage.py check
```

---

## 5. Frontend (Flutter)

### 5.1 Instalación y ejecución

```powershell
cd src\frontend
flutter pub get
flutter run
```

Análisis estático:

```powershell
dart analyze
dart format .
```

### 5.2 Configuración de la URL del API

Archivo: `lib/core/config/app_config.dart`.

- `androidEmulatorBaseUrl` — emulador Android → `http://10.0.2.2:8000`
- `localhostBaseUrl` — escritorio / Chrome → `http://127.0.0.1:8000`
- `lanBaseUrl` — teléfono físico en la misma red Wi‑Fi → IP de la PC (ej. `http://192.168.x.x:8000`)

La app construye rutas absolutas como `apiBaseUrl + "/api/rabbits/"` en los servicios.

### 5.3 Capa de red

- **`ApiClient`** (`lib/core/network/api_client.dart`): cliente HTTP fino, base URL, headers JSON, soporte de `Authorization: Bearer` cuando hay `accessToken`, reintento en 401 si hay `onTokenRefresh`.
- **Servicios** (`lib/services/*.dart`): encapsulan paths (`/api/rabbits/`, `/api/sensor-readings/`, `/api/chatbot/`) y parseo JSON.

### 5.4 Estado y UI

- **Provider** para inyección de dependencias y `ChangeNotifier` en viewmodels.
- **Pestañas principales** en `main.dart`: conejos, IoT, CuniBot (chat).
- **Voz:** `VoiceViewModel`, `speech_to_text`, `flutter_tts` (ver `lib/viewmodels/voice_viewmodel.dart` y servicios asociados).

### 5.5 Chatbot en la app

- `ChatbotService` → `POST /api/chatbot/` con `includeAuthHeader: false` (ajustar si en el futuro el endpoint exige JWT).
- `ChatbotViewModel` mantiene mensajes y estado de carga.
- `ChatbotView` — UI del chat (estado vacío, chips de ayuda, accesibilidad con `Semantics`).

### 5.6 Build Android (referencia)

```powershell
cd src\frontend
flutter build apk
```

---

## 6. Seguridad y buenas prácticas

1. **Nunca** commitear `src/backend/.env` ni claves API en el código.
2. Rotar claves que se hayan filtrado en chats, issues o capturas.
3. En producción: `DEBUG=False`, `ALLOWED_HOSTS` restringido, secretos solo por variables de entorno o secret manager.
4. Revisar políticas CORS si se sirve un frontend web distinto del mismo origen que la API.

---

## 7. Solución de problemas frecuentes

| Síntoma | Causa probable | Acción |
|---------|----------------|--------|
| `ModuleNotFoundError: dotenv` | `python-dotenv` no instalado en el **venv** del backend | `pip install -r requirements.txt` con venv activo |
| `GEMINI_API_KEY is not configured` | Falta `.env` o variable vacía | Crear/editar `src/backend/.env` y reiniciar `runserver` |
| `405` en `/api/chatbot/` | Se usó GET en el navegador | Usar POST (Postman, curl, o app Flutter) |
| App no llega al API desde el móvil | URL base incorrecta o firewall | Usar IP LAN en `app_config.dart` y `runserver 0.0.0.0:8000` |
| Error de conexión PostgreSQL | Postgres no levantado o credenciales | Verificar servicio y variables `POSTGRES_*` |

---

## 8. Documentación relacionada

- `AGENTS.md` — comandos estándar y áreas protegidas del repo.
- `docs/chatbot-ia.md` — plan de implementación del chatbot (referencia histórica).
- `docs/TechDesign-CuniSmart-MVP.md`, `docs/PDR-CuniSmart-MVP.md` — alcance y diseño de producto.

---

## 9. Mantenimiento de este README

Actualizar este archivo cuando cambien:

- Rutas API o apps Django nuevas.
- Variables de entorno obligatorias.
- Flujo de autenticación del chatbot o del resto de endpoints.
- Requisitos de versiones (Python, Flutter SDK).

---

*Última alineación con la estructura `src/backend` + `src/frontend` del monorepo CuniSmart.*
