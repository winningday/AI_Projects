# CLAUDE.md — AI_Projects

## Rules

1. **Always update README.md** inside the relevant project folder after any code changes
2. **Always update the project's `.context/` files** when architecture, files, or features change
3. **Read `.context/overview.yaml` first** before diving into code — it has the map
4. **Don't read all source files** — use `.context/` files to find what you need, then read only those files
5. **Commit and push** after completing work — never leave uncommitted changes
6. **Branch naming**: always use `claude/` prefix with session suffix
7. **UI/UX first** — always design intuitive, polished interfaces that match the app's visual theme. Use proper toggle controls, clear labels, consistent spacing, and native macOS patterns. Never use plain text buttons where proper controls exist.

## Projects

| Folder | Description | Status |
|--------|-------------|--------|
| `VoiceTranscriber/` | **Verbalize** — macOS voice-to-text app with translation | Active |
| `rotating-gif-maker/` | Logo rotation GIF generator | Complete |

## Skills

| Command | Description |
|---------|-------------|
| `/make-icon` | Generate a properly formatted macOS `.icns` app icon from a source PNG. Handles rounded corner fixes, safe zone padding, and all required iconset sizes. |

## Quick Reference

- Primary branch pattern: `claude/<feature>-<session-id>`
- Build system: Swift Package Manager (VoiceTranscriber)
- No CI/CD — manual builds on user's Mac
- User's machine: macOS (Apple Silicon), no Swift on this dev server
