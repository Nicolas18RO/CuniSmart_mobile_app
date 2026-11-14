# System Memory & Context 🧠
<!--
AGENTS: Update this file after every major milestone, structural change, or resolved bug.
-->

## 🏗️ Active Phase & Goal
**Current phase:** R3 — **E1–E5 PASS; esquema de desarrollo corregido; E8 automatizado PASS y validación física parcial (2026-11-09)**. E6, E7 y E9 no implementados; R3 completo todavía no aprobado.
**Fórmula:** contribución `(1/2)^(n1+n2)*(1+F_A)` solo si las rutas comparten únicamente al ancestro. `expectedInbreeding = R/2`. Umbrales sobre la consanguinidad esperada: `< 1/16` SIN_ADVERTENCIA, `>= 1/16 y < 1/8` PREVENTIVO, `>= 1/8` ALTO. Dato incompleto = `NO_CALCULABLE` (coeficientes null, razón `INFORMACIÓN_GENEALÓGICA_INSUFICIENTE`), distinto de 0 real.
**Evidencia histórica no reproducida:** el registro anterior declaraba Django 142/142 y Flutter 294/294; no usarlo como gate actual.
**Intervención actual:** UNKNOWN/FOUNDER/RECORDED explícitos, migración 0009 conservadora UNKNOWN; 0010 agrega historial transaccional y checks. Bloqueo por propietario compartido con edición/eliminación Rabbit (cambio R2 acotado autorizado), refresco y versiones atómicas. Ownership fail-closed, guardia de sexo, BFS mínimo/determinista con vínculos e integridad. Dart BigInt y fixture matricial independiente de 30 grafos/1350 pares exactos en ambos lenguajes. Límites: profundidad 128, 4096 caminos/lado, 1000000 pares; exceder devuelve NO_CALCULABLE/null, no cero. Fundadores explícitos se consideran independientes dentro del registro.
**Validación final actual:** backend **177/177 PASS** (561,546 s), incluidas carreras reales PostgreSQL; Flutter **250/250 PASS**, sin omitidos. Dart analyze: 0 errores/0 advertencias y 3 infos STT preexistentes. Django check y autodetector sin diferencias. Base temporal `test_cunismart_r3_integral_20261109` eliminada (`TEMPORARY_DATABASE_REMAINS: False`). Desarrollo `cunismart_db`: respaldo custom verificado fuera del repo y migraciones `core.0009`–`0011` aplicadas; 2 conejos conservados. Smoke real: Conejos, IoT, ficha, pedigree, parentesco, eventos y calendario HTTP 200 JSON. APK debug PASS para `192.168.1.6:8000`. Informes: `docs/implementation/POSTGRESQL_SCHEMA_DIAGNOSIS.md` y `POSTGRESQL_SCHEMA_FIX_REPORT.md`.
**Historial de validación:** 147/147 y 17 focalizadas, Flutter 229/229 pertenecían al cierre PARTIAL anterior; no certificaban el código posterior. La validación 166/237 reemplaza esa conclusión solo para E1–E4. Sin commits ni cambios de rama; eliminaciones preexistentes y cambios R1/R2 ajenos preservados; ninguna prueba eliminada.
**E5 gestión reproductiva:** `ReproductiveEvent` con UUID, owner, macho/hembra inmutables, fechas de calendario, +31 días calculado por backend, notas, versión y soft delete. Capas: `reproductive_domain.py`, `reproductive_service.py`, `reproductive_repository.py`; API autenticada `/api/reproductive-events/` y `/calendar/`. Calendario por fecha probable, rango máximo 366 días y estados derivados UPCOMING/DUE_TODAY/OVERDUE. Las respuestas reutilizan E4 mediante `genealogy_herd.py` y conservan NO_CALCULABLE/null. Eventos activos protegen sexo y eliminación Rabbit bajo el bloqueo por owner. Migración 0011 validada solo en temporal. Focal E5: 11/11; integración E4–E5: 15/15; regresión backend final: **177/177 PASS** (751,591 s), dos carreras E5 reales, temporal eliminada. Flutter no ejecutado: E5 no modificó Dart. Informe: `docs/implementation/R3_E5_VALIDATION.md`.
**E8 Flutter:** Clean Architecture en `features/r3`: entidades, contrato, repositorio HTTP, casos de uso, `R3ViewModel` y vistas. ApiClient sanea HTML/trace y 500, conserva JSON seguro y separa `rawBody` para conflictos 409. Física parcial en Samsung real: sesión, Conejos, IoT, menú R3, lista y calendario reproductivo PASS, sin overflow. Pendientes: CRUD físico, relaciones/árbol, parentesco interactivo, CuniBot, voz/TalkBack y caída/reintento de red. Resultado E8 **PARTIAL/PENDING físico integral**; no marcar completo todavía.
**Endpoint:** `GET /api/rabbits/kinship/?a=&b=`
**Next:** completar el checklist físico pendiente documentado en `POSTGRESQL_SCHEMA_FIX_REPORT.md`. Commit solo si lo pide. R2 UI sin commitear sigue en el árbol.


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
# R3 E3–E4 parentesco y genealogía (2026-11-10)

- Contrato aditivo: `CALCULABLE` exacto, `PARTIAL` con mínimo demostrado y
  `NO_CALCULABLE` sin evidencia o con estado contradictorio.
- Pepe × Mónica: padre–hija, relación mínima 50 %, consanguinidad mínima 25 %,
  riesgo ALTO; Juan 2 hereda ese mínimo individual.
- Árbol con etiquetas semánticas; Flutter no muestra generaciones negativas.
- Validación: backend 180/180, Flutter 253/253, analyze sin errores, sin deriva
  de migraciones y APK debug generado. Prueba física/TalkBack pendiente.

# R3 fundadores externos independientes (2026-11-10)

- `FOUNDER` se formalizó como raíz externa declarada; `UNKNOWN` no supone
  independencia y `RECORDED` sigue derivado de ambos padres.
- Flutter transporta `genealogy_knowledge` offline-first; SQLite v3 agrega la
  columna con `UNKNOWN` y preserva datos v2.
- El formulario permite declarar fundador con confirmación explícita.
- API añade `independenceAssumptionApplied` y `declaredFounders`; 0 % se explica
  como exacto dentro del modelo, no como certeza biológica.
- Validación: backend 183/183, Flutter 257/257, analyze sin errores, PostgreSQL
  sin cambios y APK debug generado. Prueba física pendiente.

