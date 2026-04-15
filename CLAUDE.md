---
type: root-config
scope: monorepo
purpose: Claude Code operating instructions for AI_Projects monorepo
read: ALWAYS — this is your entry point
---

# CLAUDE.md — AI_Projects Monorepo

## 1. Monorepo Isolation (CRITICAL)

This repo contains **independent projects in separate folders**. You MUST:

- **Only touch the project folder you're working on.** Never read, search, or modify sibling directories.
- **Never `git pull origin main`** — this pulls ALL projects. Instead:
  ```bash
  git fetch origin main
  git checkout origin/main -- <project-folder>/
  ```
- **Always sync before working** — fetch the latest version of your project folder before making changes.

## 2. Context System — Read Smart, Not Everything

Every project uses a **layered context system** to minimize token usage. Follow this lookup order:

```
1. Root CLAUDE.md          ← You are here. Project index + global rules.
2. <project>/CLAUDE.md     ← Project-specific rules, stack, build commands.
3. <project>/.context/     ← Architecture, file maps, decisions. Read overview.yaml FIRST.
4. <project>/MEMORY.md     ← Session log. What was done, what's pending, gotchas.
5. <project>/TODO.md       ← Active tasks for this project.
6. <project>/README.md     ← User-facing docs. Update after code changes.
```

### Rules

- **All documentation files MUST have YAML frontmatter** describing `type`, `scope`, and `purpose` so you can decide whether to read them without opening the full file.
- **Never read all source files.** Use `.context/overview.yaml` to find the file you need, then read only that file.
- **If a doc exceeds ~200 lines**, split it. Create a summary hub that references sub-documents. Each sub-doc gets its own YAML frontmatter.
- **Prefer YAML over prose** for structured data (file maps, architecture, decisions).

## 3. Memory System

Each project has a `MEMORY.md` — a **running log of what Claude Code has done and learned**. This is how context persists across sessions.

### When to write to MEMORY.md

- After completing any task (what you did, files changed)
- When you discover a gotcha or non-obvious behavior
- When a decision is made about architecture or approach
- When a bug is fixed (root cause + fix summary)

### Format

```yaml
---
type: memory-log
scope: <project-name>
purpose: Persistent session memory for Claude Code
last_updated: YYYY-MM-DD
---
```

Entries are reverse-chronological (newest first). Each entry:

```markdown
## YYYY-MM-DD — <Brief Title>

- **What:** One-line summary of work done
- **Files:** List of files created/modified
- **Decisions:** Any architectural or design choices made
- **Gotchas:** Non-obvious things future sessions should know
- **Next:** What to pick up next (if applicable)
```

Keep entries **compact**. If details are needed, reference a file path rather than inlining content.

## 4. Task Management (GTD-Inspired)

### Root TODO.md

Cross-project task overview. Only contains **project names + status + next action**. Details live in each project's `TODO.md`.

### Project TODO.md

Each active project maintains its own `TODO.md`:

```yaml
---
type: task-list
scope: <project-name>
purpose: Active and planned tasks
last_updated: YYYY-MM-DD
---
```

Structure:

```markdown
## In Progress
- [ ] Task description → `detail-ref: .context/some-file.yaml#section` (if complex)

## Up Next
- [ ] Task description

## Done (Recent)
- [x] Task description (YYYY-MM-DD)

## Backlog
- [ ] Task description
```

Rules:
- **One "In Progress" task at a time per project.** Finish or park before starting another.
- **Move completed tasks to "Done (Recent)".** Prune monthly — archive old items to MEMORY.md.
- **Complex tasks** get a detail file in `.context/` rather than bloating TODO.md.
- **Always update TODO.md** when starting or finishing work.

## 5. Document Conventions

### YAML Frontmatter (Required on ALL .md and .yaml docs)

```yaml
---
type: config | context | memory-log | task-list | readme | architecture | reference
scope: repo | <project-name>
purpose: <one-line description so Claude can skip if irrelevant>
last_updated: YYYY-MM-DD          # optional but recommended
---
```

### Code Documentation

- **Don't add comments to code you didn't change.**
- Source files in `.context/overview.yaml` should have a one-line description so Claude can find the right file without reading all source.
- For complex modules, add a brief `# Module: <purpose>` comment at the top — nothing more.

### Document Splitting Rules

| Lines | Action |
|-------|--------|
| < 200 | Keep as single file |
| 200–400 | Add a table of contents with anchor links |
| > 400 | Split into hub + sub-documents in `.context/` |

Hub files contain only: frontmatter + summary + links to sub-docs.

## 6. Project Index

| Folder | Status | Stack | CLAUDE.md | .context/ | MEMORY.md | TODO.md |
|--------|--------|-------|-----------|-----------|-----------|---------|
| `VoiceTranscriberAPI/` | Active | TypeScript, Hono, Cloudflare Workers, D1 | Yes | Yes | Needed | Needed |
| `VoiceTranscriber/` | Active | Swift, SwiftUI, GRDB, OpenAI, Anthropic | Needed | Yes | Needed | Needed |
| `instagram-assistant/` | Active | Python, Streamlit, SQLite, Claude | Needed | No | Needed | Needed |
| `resume-maker/` | Active | Python, RenderCV, Claude API | Needed | No | Needed | Needed |
| `video_editor/` | Active | Python, ffmpeg, Whisper, Claude Vision | Needed | No | Needed | Needed |
| `watercolor_editor/` | Active | Python, ffmpeg, multi-stage pipeline | Needed | No | Needed | Needed |
| `VoiceTranscriber-Windows/` | Active | C#, WPF, .NET 8, NAudio, SQLite | Yes | Yes | Yes | Yes |
| `rotating-gif-maker/` | Complete | Python, PIL, OpenCV | Has one | No | No | No |
| `youtube-mastermind/` | Active | Claude Code, 8 Agents, YAML config | Yes | Yes | Yes | Yes |

**"Needed"** = create these files when you first work on that project. Use the templates in this document.

## 7. Session Startup Checklist

Every time you start working on a project:

1. **Read this file** (root CLAUDE.md) — you're doing it now.
2. **Sync the project folder**: `git fetch origin main && git checkout origin/main -- <project>/`
3. **Read `<project>/CLAUDE.md`** if it exists — project-specific rules.
4. **Read `<project>/MEMORY.md`** if it exists — pick up where you left off.
5. **Read `<project>/TODO.md`** if it exists — know what's active.
6. **Read `<project>/.context/overview.yaml`** if it exists — get the file map.
7. **Only then** read source files as needed.

## 8. Session Shutdown Checklist

Before ending work:

1. **Update `MEMORY.md`** with what you did this session.
2. **Update `TODO.md`** — mark done items, add new ones discovered.
3. **Update `.context/` files** if architecture, files, or features changed.
4. **Update `README.md`** if user-facing behavior changed.
5. **Commit and push.** Never leave uncommitted changes.

## 9. Global Rules

- **Branch naming**: `claude/<feature>-<session-id>`
- **UI/UX first**: Design intuitive, polished interfaces. Use proper native controls, consistent spacing, clear labels. Never use plain text where proper controls exist.
- **No CI/CD**: Manual builds on user's Mac (Apple Silicon). No Swift compiler on dev server.
- **Commit often**: Small, focused commits with clear messages.
- **Don't over-engineer**: Only make changes that are directly requested or clearly necessary.

## 10. Skills

| Command | Use When |
|---------|----------|
| `/design-icon` | Need to create/redesign an app icon. Interactive Q&A → AI image gen prompts. |
| `/make-icon` | Have a PNG, need a macOS `.icns`. Handles corners, padding, all sizes. |
| `/apply` | Resume maker — takes a job description, generates resume + cover letter + interview prep. |

> **Global install:** Copy `.claude/skills/` to `~/.claude/skills/` to use across all projects.
