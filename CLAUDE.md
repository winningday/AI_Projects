# CLAUDE.md — AI_Projects

## Rules

1. **Stay in scope** — this is a monorepo. Each folder is an independent project. Only read, search, and modify files inside the specific project folder you're working on. Never touch sibling project directories.
2. **Keep branches clean** — when you need to pull updates from main, do NOT run `git pull origin main` or `git merge origin/main` as this drags in every project's files. Instead, cherry-pick only the commits relevant to your project, or use `git checkout origin/main -- <project-folder>/` to pull just the files you need from a specific subdirectory.
3. **Always update README.md** inside the relevant project folder after any code changes
4. **Always update the project's `.context/` files** when architecture, files, or features change
5. **Read `.context/overview.yaml` first** before diving into code — it has the map
6. **Don't read all source files** — use `.context/` files to find what you need, then read only those files
7. **Commit and push** after completing work — never leave uncommitted changes
8. **Branch naming**: always use `claude/` prefix with session suffix
9. **UI/UX first** — always design intuitive, polished interfaces that match the app's visual theme. Use proper toggle controls, clear labels, consistent spacing, and native macOS patterns. Never use plain text buttons where proper controls exist.

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
