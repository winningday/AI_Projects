---
type: task-list
scope: VoiceTranscriberIOS
purpose: Active and planned tasks
last_updated: 2026-03-18
---

## In Progress
- [ ] Build and test on real iOS device

## Up Next
- [ ] Add long-press backspace for continuous delete
- [ ] Add autocomplete/suggestion bar above keyboard
- [ ] Add swipe-to-type gesture support
- [ ] Add keyboard sound/haptic feedback on key press
- [ ] Test keyboard extension memory usage under load
- [ ] Add app icon (use /design-icon workflow)

## Done (Recent)
- [x] Add keyboardType-based input context detection for Claude prompt (2026-03-18)
- [x] Add inputContextHint parameter to ClaudeClient (2026-03-18)
- [x] Create complete iOS project structure (2026-03-16)
- [x] Port shared code (API clients, database, config, models) (2026-03-16)
- [x] Build main iOS app with all views (2026-03-16)
- [x] Build custom keyboard extension with QWERTY layout + mic button (2026-03-16)
- [x] Set up App Group for shared data (2026-03-16)
- [x] Port CorrectionTracker for keyboard extension (2026-03-16)
- [x] Create onboarding flow with keyboard setup guide (2026-03-16)
- [x] Create project documentation (2026-03-16)

## Backlog — Keyboard Improvements
- [ ] iPad layout optimization (wider keyboard)
- [ ] Dark/light mode polish for keyboard
- [ ] Keyboard height adjustment settings
- [ ] Shortcut phrases / text expansion

## Backlog — Cloud Sync & User Auth
> Detailed plan: `.context/cloud-sync-plan.yaml`

- [ ] Phase 1: Build sync API backend (Cloudflare Workers + D1)
  - [ ] Set up Cloudflare Worker project (VoiceTranscriberAPI/)
  - [ ] Create D1 database schema
  - [ ] Implement auth endpoints (register, login, refresh, logout)
  - [ ] Implement sync endpoints (settings, dictionary, corrections, transcripts)
  - [ ] Add JWT middleware + rate limiting
  - [ ] Deploy and test
- [ ] Phase 2: Add auth + sync to iOS app
  - [ ] Build AuthClient and SyncClient
  - [ ] Build LoginView and RegisterView
  - [ ] Build SyncManager (sync-on-launch + change triggers)
  - [ ] Add offline queue for pending changes
  - [ ] Add deviceSource field to transcripts
  - [ ] Add sync status indicator in UI
- [ ] Phase 3: Add auth + sync to macOS app
- [ ] Phase 4: Add Google/Apple OAuth (future)
- [ ] Phase 5: Freemium tier enforcement (future)

## Backlog — Other
- [ ] Widget for quick stats
- [ ] Siri Shortcuts integration
