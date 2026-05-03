# System Memory & Context 🧠
<!--
AGENTS: Update this file after every major milestone, structural change, or resolved bug.
DO NOT delete historical context if it is still relevant. Compress older completed items.
-->

## 🏗️ Active Phase & Goal
**Current Task:** Instantiate agent instruction templates and prepare the repo to begin Phase 1 MVP build.
**Next Steps:**
1. Scaffold Flutter app + Django REST backend per `agent_docs/tech_stack.md`
2. Implement Phase 1 MVP features incrementally (one feature at a time) with verification

## 📂 Architectural Decisions
*(Log specific choices made during the build here so future agents respect them)*
- 2026-05-03 - Chose Flutter + Django REST + PostgreSQL for MVP (per Tech Design) to support offline-first + accessibility + IoT needs with a familiar stack.
- 2026-05-03 - MVP will be offline-first: local persistence is required for animal registration; sync strategy TBD (not specified in Tech Design).

## 🐛 Known Issues & Quirks
*(Log current bugs or weird workarounds here)*
- Tech Design does not specify IoT communication protocol or sensor hardware; integration will require a concrete choice before implementation.
- Tech Design does not specify exact project folder layout or deployment steps; these will be defined during scaffolding.

## 📜 Completed Phases
- [ ] Initial scaffold
- [ ] Database schema creation
- [ ] Voice + accessibility baseline
- [ ] IoT ingestion + dashboard
- [ ] Alerts

