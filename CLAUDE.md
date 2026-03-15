# CLAUDE.md — AI_Projects

## Rules

1. **Stay in scope** — only read, search, and explore files inside the specific project folder you're working on. Never browse or pull files from sibling project directories. This is a monorepo — each folder is an independent project.
2. **Always update README.md** inside the relevant project folder after any code changes
3. **Always update the project's `.context/` files** when architecture, files, or features change
4. **Read `.context/overview.yaml` first** before diving into code — it has the map
5. **Don't read all source files** — use `.context/` files to find what you need, then read only those files
6. **Commit and push** after completing work — never leave uncommitted changes
7. **Branch naming**: always use `claude/` prefix with session suffix
8. **UI/UX first** — always design intuitive, polished interfaces that match the app's visual theme. Use proper toggle controls, clear labels, consistent spacing, and native macOS patterns. Never use plain text buttons where proper controls exist.

## Projects

| Folder | Description | Status |
|--------|-------------|--------|
| `VoiceTranscriber/` | **Verbalize** — macOS voice-to-text app with translation | Active |
| `rotating-gif-maker/` | Logo rotation GIF generator | Complete |

## Skills

| Command | Description |
|---------|-------------|
| `/design-icon` | Interactive icon design workflow. Asks questions one at a time about your app, audience, and style, then generates 3 optimized prompts for AI image generators (Gemini, DALL-E, Midjourney, Recraft, etc.) with exact macOS icon specs baked in. Supports iteration until you get the perfect logo. |
| `/make-icon` | Convert a source PNG into a properly formatted macOS `.icns` file. Handles rounded corner fixes (`--fix-corners`), safe zone padding (`--padding`), and all required iconset sizes. Use after `/design-icon` to finalize. |

> **Global install:** Copy `.claude/skills/design-icon/` and `.claude/skills/make-icon/` to `~/.claude/skills/` to use across all projects.

## Quick Reference

- Primary branch pattern: `claude/<feature>-<session-id>`
- Build system: Swift Package Manager (VoiceTranscriber)
- No CI/CD — manual builds on user's Mac
- User's machine: macOS (Apple Silicon), no Swift on this dev server
