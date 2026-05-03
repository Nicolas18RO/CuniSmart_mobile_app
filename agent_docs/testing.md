# Testing Strategy

## Frameworks
- **Mobile Unit/Widget Tests:** `flutter test`
- **Backend Unit/Integration Tests:** `python manage.py test`
- **E2E Tests:** TBD (not specified in Tech Design; start with manual golden-path checks first)

## Manual Checks (MVP-critical)
- **Offline checks:** Airplane mode: animal registration + view/edit still works; dashboard loads cached/local data.
- **Accessibility checks:** Screen reader compatibility; voice navigation/audio feedback works on core screens.
- **Alerts checks:** Threshold triggers produce both visual + audio feedback.

## Pre-commit Hooks
- Optional (add later if desired): run `dart format --set-exit-if-changed .`, `dart analyze`, `flutter test`, and `python manage.py test`.

## Verification Loop
- After each feature: run the relevant automated tests + do a quick manual check for offline + accessibility impact.

## Execution
- **Run all mobile tests:** `flutter test`
- **Analyze mobile:** `dart analyze`
- **Run all backend tests:** `python manage.py test`

