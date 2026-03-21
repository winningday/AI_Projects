---
type: task-list
scope: repo
purpose: Cross-project task overview — details live in each project's TODO.md
last_updated: 2026-03-18
---

# TODO — AI_Projects

## Active Projects

| Project | Status | Current Focus | Next Action |
|---------|--------|---------------|-------------|
| VoiceTranscriber | Active | Maintenance | Check open bug: transcription not working → see `VoiceTranscriber/TODO.md` |
| VoiceTranscriberIOS | Active | Cloud sync planning | Build sync API backend → see `VoiceTranscriberIOS/TODO.md` |
| VoiceTranscriberAPI | Active | Phase 1 built | Deploy + test backend → see `VoiceTranscriberAPI/README.md` |
| instagram-assistant | Active | Phase 2 | Implement comment scraping → see `instagram-assistant/TODO.md` |
| resume-maker | Active | Stable | No immediate tasks |
| video_editor | Active | Development | Continue pipeline work → see `video_editor/TODO.md` |
| watercolor_editor | Active | Development | Continue pipeline work → see `watercolor_editor/TODO.md` |
| rotating-gif-maker | Complete | — | — |

## Cross-Project: Verbalize Cloud Sync

> Full plan: `VoiceTranscriberIOS/.context/cloud-sync-plan.yaml`

- [ ] Phase 1: Build sync API backend (`VoiceTranscriberAPI/` — Cloudflare Workers + D1)
- [ ] Phase 2: Wire up iOS app (auth + sync)
- [ ] Phase 3: Wire up macOS app (auth + sync)
- [ ] Phase 4: Add OAuth providers (Google, Apple)
- [ ] Phase 5: Freemium tier enforcement

## Repo-Level Tasks

- [x] Redesign CLAUDE.md with smart context system (2026-03-16)
- [x] Create memory + task management system (2026-03-16)
- [ ] Add CLAUDE.md to each active project (create as you work on each project)
- [ ] Add .context/ directories to projects that lack them
- [ ] Add YAML frontmatter to all existing documentation files
