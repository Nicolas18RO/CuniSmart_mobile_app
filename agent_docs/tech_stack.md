# Tech Stack & Tools

- **Frontend (Mobile):** Flutter (Dart)
- **Backend (API):** Django + Django REST Framework
- **Database:** PostgreSQL (via `psycopg2`)
- **Styling/UI:** Flutter Material (accessible, minimal UI)
- **Accessibility:** Voice navigation + audio feedback (implementation details TBD during build; PRD requires screen reader compatibility)

## Setup Commands (from Tech Design)

### Backend (Django REST)

```bash
python -m venv venv
# (Activate venv: Windows PowerShell example)
# .\venv\Scripts\Activate.ps1
pip install django djangorestframework psycopg2
django-admin startproject cunismart_backend
cd cunismart_backend
python manage.py startapp core
```

### Mobile (Flutter)
```bash
flutter create cunismart_mobile
cd cunismart_mobile
flutter pub get
flutter run
```

## Error Handling Pattern

### Backend (DRF): canonical API error shape
```python
from rest_framework.response import Response
from rest_framework import status

def error_response(code: str, message: str, *, details=None, http_status=status.HTTP_400_BAD_REQUEST):
    payload = {"error": {"code": code, "message": message}}
    if details is not None:
        payload["error"]["details"] = details
    return Response(payload, status=http_status)
```

### Mobile (Flutter): canonical UI-safe error mapping
```dart
class AppError implements Exception {
  final String code;
  final String message;
  final Object? cause;
  AppError(this.code, this.message, {this.cause});
}
```

## Naming Conventions
- **Dart files:** `snake_case.dart`
- **Dart classes/widgets:** `PascalCase`
- **Dart vars/functions:** `camelCase`
- **Python modules:** `snake_case.py`
- **Python classes:** `PascalCase`
- **Python functions/vars:** `snake_case`
- **Constants/env vars:** `UPPER_SNAKE_CASE`

