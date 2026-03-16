---
type: config
scope: VoiceTranscriberIOS
purpose: Project-specific rules and context for Claude Code
last_updated: 2026-03-16
---

# VoiceTranscriberIOS — Claude Code Instructions

## Project Overview

Verbalize for iOS — voice-to-text app with custom keyboard extension. Port of the macOS VoiceTranscriber app.

## Stack

- Swift 5.9, SwiftUI, UIKit (keyboard extension)
- GRDB (SQLite) for transcript storage
- OpenAI Whisper API + Anthropic Claude API
- App Groups for shared data
- XcodeGen for project generation

## Architecture

- **Shared/** — Code shared between main app and keyboard extension (API clients, database, config, models, utils)
- **VoiceTranscriberIOS/** — Main iOS app (tab-based navigation)
- **VerbalizeKeyboard/** — Custom keyboard extension (UIInputViewController + SwiftUI)

## Key Design Decisions

1. **App Group** (`group.com.verbalize.ios`) — UserDefaults and SQLite database shared between app and keyboard
2. **SharedConfig singleton** — Uses App Group UserDefaults, with `reload()` for keyboard extension to pick up app changes
3. **No hotkey system** — iOS uses keyboard extension mic button instead of macOS hotkey
4. **No text injection** — Keyboard extension uses `textDocumentProxy.insertText()` directly
5. **No context awareness by app name** — iOS doesn't expose active app; uses default style tone instead
6. **CorrectionTracker** — Monitors `textDidChange` in keyboard extension to detect user edits

## Build

```bash
# Generate Xcode project (requires XcodeGen)
xcodegen generate

# Open in Xcode
open VoiceTranscriberIOS.xcodeproj
```

Cannot build on dev server — requires Xcode on macOS with iOS SDK.

## Important Notes

- Keyboard extensions have ~50MB memory limit
- Keyboard needs "Allow Full Access" for network (API calls)
- Mic permission must be granted from main app first
- Test on real device (keyboard extension mic doesn't work in simulator)
- `RequestsOpenAccess` must be `true` in keyboard Info.plist for network + mic
