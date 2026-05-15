from __future__ import annotations

from django.conf import settings
from google import genai
from google.genai import types


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
""".strip()


def get_gemini_response(user_message: str, history: list | None = None) -> str:
    api_key = getattr(settings, "GEMINI_API_KEY", "") or ""
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY is not configured")

    client = genai.Client(api_key=api_key)

    contents: list[types.Content] = []
    for item in history or []:
        role = item.get("role")
        parts = item.get("parts", [])
        if role not in ("user", "model"):
            continue
        if not isinstance(parts, list):
            continue
        text_parts = [
            types.Part.from_text(text=str(p))
            for p in parts
            if p is not None and str(p).strip()
        ]
        if text_parts:
            contents.append(types.Content(role=role, parts=text_parts))

    contents.append(
        types.Content(
            role="user",
            parts=[types.Part.from_text(text=user_message)],
        )
    )

    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=contents,
        config=types.GenerateContentConfig(
            system_instruction=SYSTEM_PROMPT,
            temperature=0.3,
        ),
    )
    return getattr(response, "text", "") or ""

