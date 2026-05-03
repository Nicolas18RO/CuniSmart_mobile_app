# Project Brief (Persistent)

- **Product vision:** Smart rabbit farming with IoT and accessible technology
- **Target audience:** Rural rabbit farmers; includes visually impaired users (including blindness) who need voice-first interaction.

## MVP Principles (non-negotiable)
- **Accessibility-first:** Voice navigation + audio feedback for core screens; design for screen readers and strong contrast.
- **Offline-first:** Animal registration and core viewing must work without internet; sync when connection is available (sync design TBD).
- **Simplicity:** Clean, minimal UI. Clarity over complexity. Minimal steps per action.
- **Budget:** Free tools; keep monthly operating near $0.
- **Scope discipline:** Build only MVP must-haves first; explicitly exclude AI predictions and multi-user support.

## Conventions
- **Mobile naming:** Dart `snake_case.dart`, Widgets `PascalCase`, methods `camelCase`.
- **Backend naming:** Python `snake_case.py`, classes `PascalCase`, functions `snake_case`.
- **File structure (intended):**
  - `cunismart_mobile/` (Flutter app)
  - `cunismart_backend/` (Django project)

## Quality gates
- Mobile: `dart analyze`, `flutter test`, manual run on emulator/device.
- Backend: `python manage.py test`, basic API smoke checks.
- Each feature must include a quick manual check for: offline mode + voice/a11y feedback.

## Key commands
- Flutter: `flutter pub get`, `flutter run`, `flutter test`, `dart analyze`
- Django: `python -m venv venv`, `pip install ...`, `python manage.py runserver`, `python manage.py test`

## Update cadence
- Update this brief whenever you add: a new major dependency, a folder-structure decision, an IoT protocol decision, or a new verification command.

