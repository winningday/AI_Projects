---
type: memory-log
scope: instagram-assistant
purpose: Persistent session memory for Claude Code
last_updated: 2026-03-16
---

# Memory — Instagram Assistant

## 2026-03-16 — Context System Bootstrap

- **What:** Created MEMORY.md and TODO.md. No prior session history exists.
- **Files:** `MEMORY.md`, `TODO.md` (new)
- **Decisions:** Project uses Streamlit + SQLite + Claude API. Phase 1 (post management) is complete.
- **Gotchas:** Key files: `app.py` (UI), `database.py` (16KB, main logic), `scraper.py` (Phase 2), `response_generator.py` (Claude), `poster.py` (Playwright). `user_profile.md` contains brand voice guidelines.
- **Next:** Phase 2 — comment scraping implementation.
