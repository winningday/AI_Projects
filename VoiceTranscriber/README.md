# Verbalize

A privacy-first macOS voice-to-text application with real-time translation. Record your speech, transcribe it with OpenAI Whisper, clean it up with Claude, and inject the polished text into your active text field — in any language.

![Verbalize](icon.png)

## Features

- **Push-to-talk recording** — Hold your hotkey (default: Fn) to record, release to process
- **Real-time waveform** — Floating window shows audio levels while recording
- **Whisper transcription** — Fast, accurate speech-to-text via OpenAI's Whisper API (gpt-4o-mini-transcribe with whisper-1 fallback)
- **Claude cleanup** — Removes filler words, fixes stuttering, resolves self-corrections using Claude Haiku 4.5
- **Real-time translation** — Speak in any language, output in your target language (20 languages supported)
- **Context-aware formatting** — Detects your active app and adapts style (casual for Messages, formal for Email)
- **Custom dictionary** — Learns names, technical terms, and brand words for better accuracy
- **Style profiles** — Per-app tone settings (formal, casual, very casual, excited)
- **Text injection** — Cleaned text is automatically typed into your active text field
- **Productivity dashboard** — Voice WPM vs typing speed comparison, speed multiplier, time saved, weekly activity chart
- **Transcript history** — Searchable local SQLite database of all past transcriptions with WPM stats
- **Configurable hotkey** — Rebind to any key or key combination in Settings
- **Smart formatting** — Auto-detects code, technical terms, numbered lists
- **Secure key storage** — API keys stored with obfuscation in UserDefaults (auto-migrated from Keychain on upgrade)
- **Menu bar app** — Lives in the menu bar with quick translation toggle and language picker

## Supported Translation Languages

English, Spanish, French, German, Italian, Portuguese, Chinese (Simplified), Japanese, Korean, Arabic, Russian, Hindi, Dutch, Swedish, Polish, Turkish, Vietnamese, Thai, Hebrew, Ukrainian

## Requirements

- macOS 13.0 (Ventura) or later
- Swift 5.9+ / Xcode 15+ (for building)
- OpenAI API key (for Whisper transcription)
- Anthropic API key (for Claude Haiku cleanup)

## Setup

### 1. Clone and Build

```bash
git clone <repo-url>
cd VoiceTranscriber
./build.sh release --dmg
open .build/release/
open .build/release/Verbalize-1.2.0.dmg
```

This builds the app, generates the app icon from `icon.png`, and creates a DMG installer at `.build/release/Verbalize-1.2.0.dmg`.

To install directly without a DMG:
```bash
./build.sh release
# Follow the prompt to copy to /Applications
```

### 2. First Launch

On first launch, Verbalize walks you through a guided setup:

1. **Microphone permission** — Required for audio recording
2. **Accessibility permission** — Required for global hotkey and text injection
3. **API keys** — Enter your OpenAI and Anthropic keys (stored securely in UserDefaults)

### 3. API Keys

- **OpenAI API Key** — Get one at [platform.openai.com](https://platform.openai.com/api-keys)
- **Anthropic API Key** — Get one at [console.anthropic.com](https://console.anthropic.com/settings/keys)

Keys are stored with base64 obfuscation in UserDefaults. Alternatively, set environment variables:
```bash
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
```

## Usage

1. **Hold Fn** (or your configured hotkey) to start recording
2. **Speak naturally** — a floating window shows your waveform in real-time
3. **Release Fn** to stop recording and begin processing
4. Your cleaned text is automatically typed into the active text field
5. Toggle translation from the **menu bar icon** — click the globe row to enable, pick your target language

### Translation Mode

Toggle translation directly from the menu bar dropdown — no need to open settings. When enabled:
- Speak in **any language** (Chinese, Spanish, French, Arabic, etc.)
- Output is always in your selected target language
- Claude detects the source language automatically
- Natural, fluent translations — not word-for-word

### Style Profiles

Verbalize adapts its output style based on which app you're dictating into:

| App Type | Default Style | Example |
|----------|--------------|---------|
| iMessage, WhatsApp, Telegram | Casual | "hey are you free for lunch tomorrow?" |
| Slack, Teams, Discord | Formal | "Hey, are you free for lunch tomorrow?" |
| Mail, Outlook, Gmail | Formal | "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you." |
| Other (Notes, VS Code, etc.) | Formal | Full punctuation and capitalization |

Customize per-context in the **Style** tab.

### Hotkey Configuration

Open **Settings > Hotkey** to rebind. Supported options:
- Single keys (Fn, F5, etc.)
- Modifier combinations (⌥Space, ⌃⇧R, ⌘Shift+T, etc.)
- The hotkey display updates everywhere in the app automatically

## Project Structure

```
VoiceTranscriber/
├── Package.swift                          # SPM dependencies (GRDB)
├── build.sh                              # Build script (.app bundle + DMG)
├── icon.png                              # App icon source
├── logo.png                              # Logo with transparency
├── verbalize-logo.png                    # Logo on dark background
├── Verbalize-Concept.png                 # Concept mockup
├── VoiceTranscriber/
│   ├── App/
│   │   └── VoiceTranscriberApp.swift     # Entry point, AppState, window management
│   ├── Audio/
│   │   ├── AudioRecorder.swift           # AVAudioEngine recording + format conversion
│   │   └── AudioLevelMonitor.swift       # Smoothed levels for waveform UI
│   ├── API/
│   │   ├── WhisperClient.swift           # OpenAI Whisper API (gpt-4o-mini-transcribe)
│   │   └── ClaudeClient.swift            # Claude Haiku 4.5 cleanup + translation
│   ├── Database/
│   │   ├── TranscriptDatabase.swift      # GRDB SQLite storage
│   │   └── Transcript.swift              # Transcript data model
│   ├── UI/
│   │   ├── MainWindowView.swift          # Main window with sidebar navigation
│   │   ├── HomeView.swift                # Quick stats row + transcript list
│   │   ├── StatsView.swift              # Productivity dashboard (voice vs typing WPM)
│   │   ├── MenuBarView.swift             # Menu bar with translation toggle
│   │   ├── AppSettingsView.swift         # Full settings (hotkey, translation, API keys)
│   │   ├── DictionaryView.swift          # Custom dictionary management
│   │   ├── StyleView.swift               # Per-context style profiles
│   │   ├── OnboardingView.swift          # First-launch setup wizard
│   │   └── RecordingWindow.swift         # Floating waveform overlay
│   ├── Hotkey/
│   │   └── HotKeyManager.swift           # CGEvent tap + NSEvent fallback
│   └── Utils/
│       ├── TextInjection.swift           # AX API / pasteboard text injection
│       └── ConfigManager.swift           # UserDefaults config + API keys + Keychain migration
└── .gitignore
```

## Architecture

The app follows a centralized state pattern with a menu bar + window hybrid:

1. **HotKeyManager** listens for the global hotkey via CGEvent tap (with NSEvent fallback)
2. **AppState** (the orchestrator) coordinates the full pipeline:
   - Captures context from the active text field before recording starts
   - Starts **AudioRecorder** (AVAudioEngine, 16kHz mono) and shows the waveform overlay
   - On release, sends audio to **WhisperClient** with dictionary hints
   - Detects app context and selects the appropriate style tone
   - Passes raw text to **ClaudeClient** for cleanup + optional translation
   - Saves to **TranscriptDatabase** (GRDB/SQLite)
   - Uses **TextInjector** to type the cleaned text into the active app
3. **MenuBarExtra** provides persistent UI with translation toggle and quick actions
4. **MainAppWindow** (NSWindow subclass) provides the full settings/dashboard interface

Window management uses `isReleasedWhenClosed = false` and a custom `WindowDelegate` that hides instead of closing, preventing the `_NSWindowTransformAnimation` crash.

## Dependencies

| Package | Purpose |
|---------|---------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite database for transcript history |

All other functionality uses native frameworks: AVFoundation, AppKit, SwiftUI, Security, Quartz Event Services.

## Upgrading

To upgrade Verbalize to a new version, just build and replace — no uninstall needed:

```bash
# 1. Quit Verbalize (click menu bar icon → Quit)
# 2. Build the new version
./build.sh release --dmg

# 3. Open the DMG
open .build/release/Verbalize-1.2.0.dmg

# 4. Drag Verbalize.app to /Applications and click Replace when prompted
# 5. Eject the DMG and launch Verbalize
```

Or without a DMG:
```bash
./build.sh release
# Follow the prompt to copy to /Applications (replaces the old version)
```

All your settings, API keys, transcript history, dictionary, and style profiles are preserved automatically. If upgrading from v1.1, API keys are migrated from Keychain to UserDefaults on first launch.

## Clean Uninstall

To completely remove Verbalize and all its data:

```bash
# 1. Quit the app
# 2. Delete the app
rm -rf /Applications/Verbalize.app

# 3. Delete app data and database
rm -rf ~/Library/Application\ Support/Verbalize
rm -rf ~/Library/Application\ Support/VoiceTranscriber  # old name if present

# 4. Delete preferences
defaults delete com.verbalize.app 2>/dev/null

# 5. Remove from System Settings > Privacy & Security > Accessibility
#    (open manually and remove Verbalize from the list)

# 6. If System Settings feels slow, relaunch it
```

## Troubleshooting

**Hotkey not working:**
- Ensure Accessibility permission is granted in System Settings > Privacy & Security > Accessibility
- After rebuilding, you may need to remove and re-add the app in Accessibility settings
- Some keys (like Fn) may behave differently on external keyboards

**No text injection:**
- Ensure Accessibility permission is granted
- The target app must have a focused text field
- Falls back to clipboard paste (Cmd+V) if direct injection fails

**API errors / transcription not working:**
- Verify your API keys are correct in Settings
- Check your OpenAI/Anthropic account has sufficient credits
- Ensure network connectivity

**System Settings lagging:**
- If you deleted and rebuilt the app, the old entry in Accessibility settings may cause lag
- Remove the stale entry from Privacy & Security > Accessibility and relaunch System Settings

**Window doesn't open on launch:**
- Click the menu bar icon (mic icon) and select "Open Verbalize"
- The main window should open automatically on launch after onboarding is complete

## License

MIT
