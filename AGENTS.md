# AGENTS.md — Master Plan for CuniSmart

## Project Overview & Stack
**App:** CuniSmart
**Overview:** CuniSmart is a mobile app for rural rabbit farmers (including visually impaired users) to register and track rabbits, monitor farm conditions via IoT sensors (weight/temperature/water), and receive accessible real-time alerts with voice navigation and audio feedback. The MVP prioritizes offline-first usage with simple, minimal UI.
**Stack:** Flutter (mobile) + Django REST Framework (backend API) + PostgreSQL (database)
**Critical Constraints:** Android-first mobile experience, accessibility-first (voice + screen reader compatibility + high contrast), offline-first (local persistence + later sync), minimal budget (free tools), MVP scope only (no AI predictions, no multi-user).

## Setup & Commands
Execute these commands for standard development workflows. Do not invent new package manager commands.

## Project Structure (Source of Truth)

All development must follow this repository structure strictly:

- Backend (Django REST): src/backend/
- Frontend (Flutter): src/frontend/

Backend rules:
- Django project MUST exist inside src/backend/
- All apps (e.g. core, rabbits, sensors) must be created inside src/backend/
- Do NOT create a new Django project outside this directory
- Assume manage.py is located in src/backend/

Frontend rules:
- Flutter app lives in src/frontend/
- Do NOT create multiple Flutter projects

Environment rules:
- Python virtual environment is located in src/backend/venv/
- If venv exists, reuse it
- Do NOT create multiple virtual environments

### Mobile (Flutter)
- **Setup:** `flutter pub get`
- **Development:** `flutter run`
- **Testing:** `flutter test`
- **Linting & Formatting:** `dart format .` and `dart analyze`
- **Build:** `flutter build apk`

### Backend (Django REST)
- **Setup (env):** `python -m venv venv` then activate venv
- **Install deps:** `pip install django djangorestframework psycopg2`
- **Development:** `python manage.py runserver`
- **Testing:** `python manage.py test`

## Protected Areas
Do NOT modify these areas without explicit human approval:
- **Infrastructure / deployment:** `.github/workflows/`, Dockerfiles (if added), and hosting config.
- **Database migrations:** Existing migration files once created.
- **Third-party integrations:** IoT device protocol choices, auth approach (if/when introduced), and any paid services.

## Coding Conventions
- **Architecture rules:** Keep business logic out of UI/widgets and out of HTTP controllers; put it in `services/` / `domain/` modules (see `agent_docs/code_patterns.md`).
- **Offline-first:** Always design flows to work without internet. Prefer local persistence as the source of truth, then sync when connectivity exists.
- **Accessibility:** Every core flow must be usable with voice navigation/audio feedback; avoid UI-only confirmations.
- **Scope discipline:** Do not add features outside MVP must-haves.

## How I Should Think
1. **Understand Intent First**: Before answering, identify what the user actually needs
2. **Ask If Unsure**: If critical information is missing, ask before proceeding
3. **Plan Before Coding**: Propose a plan, ask for approval, then implement
4. **Verify After Changes**: Run tests/linters or manual checks after each change
5. **Explain Trade-offs**: When recommending something, mention alternatives

## Agent Behaviors
These rules apply across all AI coding assistants (Cursor, Copilot, Claude, Gemini):
1. **Plan Before Execution:** ALWAYS propose a brief step-by-step plan before changing more than one file.
2. **Refactor Over Rewrite:** Prefer refactoring existing functions incrementally rather than rewriting large blocks.
3. **Context Compaction:** Write state to `MEMORY.md` (or a short spec in `specs/`) instead of bloating chat history.
4. **Iterative Verification:** Run tests/linters after each logical change. Fix errors before proceeding (see `REVIEW-CHECKLIST.md`).
5. **Accessibility & Offline Proof:** For each user-visible feature, include a quick manual test plan for offline + voice/a11y.

## MVP Phases (from PRD)
### Phase 1 (MVP Must-Haves)
- Animal Registration (create/edit/view; saved locally)
- Voice Navigation & Accessibility (voice interaction + audio feedback)
- IoT Sensor Integration (display sensor data: weight/temperature/water; periodic updates)
- Real-Time Alerts (threshold-based notifications + audio feedback)
- Simple Monitoring Dashboard (animals + sensor overview; minimal layout)

### Phase 2 (Nice-to-Haves if time allows)
- Basic statistics (average weight, trends)
- Simple filtering of animals

### Not in MVP
- AI predictions
- Multi-user support

## Current State
- Repo currently contains PRD + Tech Design + templates only.
- Next implementation step is to scaffold the Flutter app and Django REST backend following `agent_docs/tech_stack.md` and `agent_docs/code_patterns.md`.

