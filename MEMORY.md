# System Memory & Context 🧠
<!--
AGENTS: Update this file after every major milestone, structural change, or resolved bug.
-->

## 🏗️ Active Phase & Goal
**Current phase:** R1.6.5 validación automatizada **PASS**. R1 **no cerrado**: falta TalkBack en dispositivo y biometría física.
**Next steps (priority):**
1. Recorreo manual en emulador + TalkBack (checklist en `docs/reviews/R1_6_5_VALIDACION.md`)
2. Biometría en teléfono físico (opt-in Seguridad; no enviar muestras)
3. R2+: `IsAuthenticated` + FK `user` en Rabbit

## 📂 Architectural Decisions
- **Stack:** Flutter + Django REST + PostgreSQL (`src/frontend/`, `src/backend/`).
- **Mobile pattern:** MVVM + Provider; `AsyncViewState` for lists; services own HTTP.
- **Auth:** JWT (Simple JWT), refresh in `flutter_secure_storage`. Password reset one-time. Logout remoto. Biometría opt-in via Seguridad → PUT `biometric-status` (solo flag); lock al bootstrap si flag + hardware.
- **IoT (current):** `SensorDevice` + `SensorReading`; dev data via `simulate_sensor_readings`; client polls API every 4s.
- **Alerts (current):** UI-only heuristics in `iot_dashboard_view.dart` — not backend push, not TTS on alert.
- **Chatbot:** `POST /api/chatbot/` → Gemini (`google-genai`); no auth on endpoint (dev risk).
- **PRD offline-first:** NOT implemented — all rabbit/sensor data is server-backed only.

## 🐛 Known Issues & Quirks
- `AGENTS.md` still says "templates only" — **false**; see `docs/CONTEXTO_MAESTRO.md`.
- `docs/TechDesign-CuniSmart-MVP.md` is truncated; use `docs/README-TECNICO-CuniSmart.md` + code.
- `widget_test.dart` ya no monta `CuniSmartApp` (R1.1). El fallo R1.0 (`notifyListeners` en `AppRoot.initState` + título Conejos) sigue si se bomba la app completa.
- `Rabbit` model has no `user` FK — global farm data for all authenticated users.
- Hardcoded LAN IP in `app_config.dart` (backend public URL now from env).
- Duplicate auth UI paths removed in R1.5; official tree is `features/auth` + `BiometricLockScreen`.

## 📜 Completed Phases
- [x] Initial scaffold (Flutter + Django in `src/`)
- [x] Database schema (Rabbit, SensorDevice, SensorReading, User, UserSettings)
- [x] Rabbit CRUD (API + UI + voice commands)
- [x] Voice + accessibility baseline (STT/TTS, navigation, voice forms)
- [x] IoT display + polling + simulation command
- [x] Alerts (visual only, in IoT dashboard)
- [x] Auth (JWT, email verify, biometric lock)
- [x] R1.0 línea base de tests (`docs/reviews/R1_BASELINE_TEST_REPORT.md`)
- [x] R1.1 tests comportamiento actual (`docs/reviews/R1_1_CURRENT_BEHAVIOR_TESTS.md`; `accounts/tests.py` + `test/auth/*`)
- [x] R1.2 password reset (`docs/reviews/R1_2_PASSWORD_RESET.md`)
- [x] R1.3 sesión / logout remoto (`docs/reviews/R1_3_SESSION.md`)
- [x] R1.4 biometría opt-in (`docs/reviews/R1_4_BIOMETRIC.md`)
- [x] R1.6.5 validación automatizada (`docs/reviews/R1_6_5_VALIDACION.md`)
- [x] CuniBot chat (Gemini)
- [ ] Offline-first local DB + sync
- [ ] Alert audio / system notifications
- [ ] Per-user data isolation
- [ ] Real IoT device integration

## 📎 Canonical context doc
Full audit: **`docs/CONTEXTO_MAESTRO.md`**
