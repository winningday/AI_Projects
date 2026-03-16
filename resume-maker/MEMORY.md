---
type: memory-log
scope: resume-maker
purpose: Persistent session memory for Claude Code
last_updated: 2026-03-16
---

# Memory — Resume Maker

## 2026-03-16 — Context System Bootstrap

- **What:** Created MEMORY.md and TODO.md. Project is stable and functional.
- **Files:** `MEMORY.md`, `TODO.md` (new)
- **Decisions:** Uses `/apply` slash command defined in `.claude/commands/apply.md`. Output goes to `outputs/<company>_<role>_<date>/`. Uses RenderCV for PDF generation.
- **Gotchas:** `ABOUTME.md` is the personal background database — must be filled out before using. `generate_resume.py` exists for standalone use but `/apply` is the primary workflow.
- **Next:** No immediate tasks. Project is stable.
