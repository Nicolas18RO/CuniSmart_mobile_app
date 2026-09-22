# System Memory & Context 🧠
<!--
AGENTS: Update this file after every major milestone, structural change, or resolved bug.
-->

## 🏗️ Active Phase & Goal
**Current phase:** Voice Fix Cycle — **impl cerrado**. Suite voz **81/81**. Volume **Up** long-press; corrección desde CONFIRMING; hoy/ayer/antier + TTS natural.
**Artefactos:** `VOICE_CORRECTION_DATE_BUTTON_{AUDIT,TDD,IMPLEMENTATION}.md`
**Next steps (priority):**
1. Validación física checklist (Vol↑, corregir en confirmación, fechas relativas) en Android.
2. Si Vol↑ no responde en un OEM → FAB.


## 📂 Architectural Decisions
- **Stack:** Flutter + Django REST + PostgreSQL (`src/frontend/`, `src/backend/`).
- **Mobile pattern:** MVVM + Provider; `AsyncViewState` for lists; services own HTTP.
- **Auth:** JWT (Simple JWT), refresh in `flutter_secure_storage`. Password reset one-time. Logout remoto. Biometría opt-in via Seguridad → PUT `biometric-status` (solo flag); lock al bootstrap si flag + hardware.
- **IoT (current):** `SensorDevice` + `SensorReading`; dev data via `simulate_sensor_readings`; client polls API every 4s.
- **Alerts (current):** UI-only heuristics in `iot_dashboard_view.dart` — not backend push, not TTS on alert.
- **Chatbot:** `POST /api/chatbot/` → Gemini (`google-genai`); no auth on endpoint (dev risk).
- **PRD offline-first:** Drift + cola + sync automático **sí** (R2.4–R2.6). Conflictos 409 con resolución de usuario **sí** (R2.7). QR local + escaneo **sí** (R2.8). Sensores siguen solo en servidor.

## 🐛 Known Issues & Quirks
- `AGENTS.md` still says "templates only" — **false**; see `docs/CONTEXTO_MAESTRO.md`.
- `docs/TechDesign-CuniSmart-MVP.md` is truncated; use `docs/README-TECNICO-CuniSmart.md` + code.
- `widget_test.dart` ya no monta `CuniSmartApp` (R1.1). El fallo R1.0 (`notifyListeners` en `AppRoot.initState` + título Conejos) sigue si se bomba la app completa.
- `Rabbit.user` + `uuid` único + `version` + `deleted_at`. DELETE lógico. Drift: `rabbits` + `sync_operations`. CRUD offline si API ≥500/red. SyncEngine drena cola al iniciar lista, al volver a foreground, al recuperar red y al pulsar actualizar. CREATE reintenta por UUID (GET si POST 400). Editar un alta aún no subida **actualiza el CREATE** (no encola un segundo UPDATE). PUT/PATCH con `version` desfasada → HTTP 409 + snapshot; cola `CONFLICT` no se reintenta sola; ficha: conservar servidor o conservar cambios locales. QR `cunismart://rabbit/<uuid>` generado local; escaneo busca Drift y si falta GET (404 si no es del usuario); sin red avisa que no está local. Tras escanear, TTS de R1 lee la ficha. TalkBack: labels y orden de foco.
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
- [x] Offline-first local DB + sync
- [ ] Alert audio / system notifications
- [x] R2.1 ownership API + migrate en `cunismart_db`
- [x] Per-user data isolation on existing PostgreSQL rabbit rows
- [x] R2.2 UUID / version / deleted_at + detalle por UUID
- [x] R2.3 CRUD + ficha + eliminación lógica
- [x] R2.4 Drift (tabla rabbits, persistencia, lectura local, sync_status)
- [x] R2.5 CRUD offline + cola persistente
- [x] R2.6 SyncEngine (conectividad, reintentos, idempotencia UUID)
- [x] R2.7 conflictos (409, CONFLICT, snapshot, resolución en ficha)
- [x] R2.8 QR (generación, escaneo, lookup UUID, ficha)
- [x] R2.9 accesibilidad (TalkBack, orden de foco, TTS ficha/QR)
- [x] R2.10 recorrido mínimo (offline, ficha, QR, persistir, sync)
- [ ] Real IoT device integration

## 📎 Canonical context doc
Full audit: **`docs/CONTEXTO_MAESTRO.md`**
