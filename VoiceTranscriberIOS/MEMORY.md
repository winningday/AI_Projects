---
type: memory-log
scope: VoiceTranscriberIOS
purpose: Persistent session memory for Claude Code
last_updated: 2026-03-16
---

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
