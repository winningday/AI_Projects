---
type: memory-log
scope: VoiceTranscriberIOS
purpose: Persistent session memory for Claude Code
last_updated: 2026-03-18
---

## 2026-03-18 — KeyboardType Context + Cloud Sync Planning

- **What:** Added keyboardType/textContentType detection so Claude gets input context hints (email field, URL field, name field, etc.). Also documented full cloud sync + user auth feature plan.
- **Files:**
  - Modified: `VerbalizeKeyboard/KeyboardViewController.swift` — added `detectInputContext()` method
  - Modified: `Shared/API/ClaudeClient.swift` — added `inputContextHint` parameter to `cleanTranscription()` and `buildSystemPrompt()`
  - Created: `.context/cloud-sync-plan.yaml` — comprehensive cloud sync architecture
  - Updated: `TODO.md` — reorganized backlog, added cloud sync phases
- **Decisions:**
  - Cloud sync will use Cloudflare Workers + D1 (SQLite-based, free tier generous, no vendor lock-in)
  - Custom email/password auth first (JWT + bcrypt), Google/Apple OAuth layered on later
  - API keys will NOT sync (security — stay local per device)
  - Sync strategy: settings = last-write-wins, dictionary = union-merge, corrections/transcripts = append-only
  - Local-first architecture: app works offline, queues changes, syncs on reconnect
  - Backend will be a new project folder: `VoiceTranscriberAPI/`
- **Gotchas:**
  - `textDocumentProxy.keyboardType` returns optional on some iOS versions — defaulting to `.default`
  - `textContentType` is more specific than `keyboardType` — check it first
  - Self-learning correction tracking is already fully wired: CorrectionTracker → SharedConfig.corrections → Claude "PAST CORRECTIONS" prompt section
- **Next:** Build the Cloudflare Workers backend (Phase 1), then wire up iOS client (Phase 2)

## 2026-03-16 — Initial iOS Port from macOS VoiceTranscriber

- **What:** Created complete iOS port of Verbalize (macOS VoiceTranscriber) with custom keyboard extension
- **Files:** Created entire project structure:
  - `Shared/` — API clients, database, config, models, utils (shared between app + keyboard)
  - `VoiceTranscriberIOS/` — Main app with tab navigation (Home, History, Stats, Dictionary, Settings)
  - `VerbalizeKeyboard/` — Custom keyboard extension with QWERTY layout + mic button
  - `project.yml` — XcodeGen spec for generating Xcode project
  - `Package.swift`, Info.plist files, entitlements
- **Decisions:**
  - Used App Group (`group.com.verbalize.ios`) for sharing data between app and keyboard extension
  - SharedConfig uses App Group UserDefaults with `reload()` method for keyboard to pick up changes
  - Keyboard is full QWERTY with number/symbol pages + blue mic button + globe key
  - No macOS-specific code: removed hotkey system, menu bar, text injection, AppKit
  - AudioRecorderIOS uses AVAudioSession (iOS) instead of AVCaptureDevice (macOS)
  - CorrectionTracker works via `textDidChange` delegate in keyboard extension
  - TranscriptDatabase uses App Group container path for SQLite file
- **Gotchas:**
  - Keyboard extensions have ~50MB memory limit — keep GRDB usage light
  - Need "Allow Full Access" enabled for network access from keyboard
  - Mic permission must be granted via main app (keyboard can't prompt)
  - Simulator doesn't support mic in keyboard extensions — test on real device
  - `textDocumentProxy` only provides limited text context (not full document)
- **Next:** Build and test on real device, polish keyboard layout, add haptic patterns
