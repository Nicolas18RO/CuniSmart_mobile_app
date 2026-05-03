# Code Patterns

## Purpose
This file defines the implementation patterns the agent should follow for this project.
Prefer these patterns over inventing new ones.

## Architecture Pattern
- **Primary pattern:** Layered + feature-based (Mobile + Backend), with clear boundaries:
  - **Mobile UI layer:** Flutter widgets/screens only
  - **Application/services layer:** orchestrates use-cases (register animal, evaluate alert thresholds, sync)
  - **Data layer:** repositories, local storage, API clients
  - **Backend transport layer:** DRF views/serializers; no business rules embedded in views
- **Rule:** Keep domain logic separate from transport/UI concerns.
- **Rule:** Reuse existing modules before creating new abstractions.

## Data Fetching / Persistence
- **Primary approach (offline-first):** local persistence first (required by PRD), then sync to backend when connectivity exists.
- **Rule:** Do not block core flows on network availability.
- **Rule:** Network calls belong in API client/repository modules, never directly in widget build methods.

## State Management (Mobile)
- **Client state:** Start simple (Flutter built-in state: `StatefulWidget` / `ValueNotifier`); introduce a state library only if needed.
- **Forms:** Prefer explicit form models + validation; keep validation close to the form contract.

## Error Handling
- Normalize errors at service/API boundaries — never let raw exceptions reach the UI.
- Never swallow errors silently; always log or surface them.
- Return user-safe messages in the UI; keep developer context in logs.
- Use a consistent error shape for API responses (see `agent_docs/tech_stack.md`).

## Validation
- Validate all external inputs (user forms, API payloads).
- Apply runtime validation at system boundaries; trust internal types inside those boundaries.

## File and Naming Conventions
- **Dart files:** `snake_case.dart`
- **Widgets/classes:** `PascalCase`
- **Functions/variables:** `camelCase`
- **Python modules:** `snake_case.py`
- **Python classes:** `PascalCase`
- **Python functions/vars:** `snake_case`
- **Constants/env vars:** `UPPER_SNAKE_CASE`

## Testing Pattern
- Add unit/widget tests for core mobile flows (animal CRUD, alert evaluation logic).
- Add backend tests for API contracts and core data flows.
- Start without E2E until core golden path is stable; prioritize manual golden-path checks first.

## Change Discipline
- Prefer focused, minimal edits over large rewrites.
- Do not introduce new dependencies without checking the existing stack in `agent_docs/tech_stack.md` first.
- Do not change migrations, CI, deployment, or IoT protocol choices without explicit approval.
- One feature at a time — checkpoint after each working feature.

