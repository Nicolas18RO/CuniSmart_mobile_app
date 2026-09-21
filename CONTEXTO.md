# CuniSmart — Contexto del proyecto

Este archivo es el **punto de entrada** al contexto maestro del repositorio.

## Documento completo

Toda la arquitectura, estado del MVP, brechas PRD ↔ código, deuda técnica y roadmap están en:

**[docs/CONTEXTO_MAESTRO.md](docs/CONTEXTO_MAESTRO.md)**

Incluye:

- Resumen ejecutivo y estado actual
- Arquitectura y módulos (backend + frontend)
- Funcionalidades implementadas, pendientes y no documentadas
- Deuda técnica y roadmap recomendado
- **Memoria del proyecto** (tabla compacta para agentes)
- Referencias a archivos clave

## Memoria rápida

| | |
|---|---|
| **Stack** | Flutter + Django REST + PostgreSQL |
| **Rutas** | `src/frontend/`, `src/backend/` |
| **Listo** | CRUD conejos, IoT UI, voz, auth JWT, CuniBot |
| **Falta (PRD)** | Offline-first, TTS en alertas, datos por usuario |
| **Agente** | Ver también `AGENTS.md` y `MEMORY.md` |

---

*Para actualizar el contexto tras un hito importante, editar `docs/CONTEXTO_MAESTRO.md` y `MEMORY.md`.*
