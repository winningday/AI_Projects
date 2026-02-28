# VoiceTranscriber

A privacy-first macOS voice-to-text application that records your speech, transcribes it with OpenAI Whisper, cleans it up with Claude, and injects the polished text into your active text field.

## Features

- **Push-to-talk recording** — Hold your hotkey (default: Fn) to record, release to process
- **Real-time waveform** — Floating window shows audio levels while recording
- **Whisper transcription** — Fast, accurate speech-to-text via OpenAI's Whisper API
- **Claude cleanup** — Removes filler words, fixes stuttering, resolves self-corrections
- **Text injection** — Cleaned text is automatically typed into your active text field
- **Transcript history** — Searchable local database of all past transcriptions
- **Configurable hotkey** — Rebind to any key or key combination in Settings
- **Secure key storage** — API keys stored in macOS Keychain, not in plaintext files

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15+ (for building)
- OpenAI API key (for Whisper)
- Anthropic API key (for Claude Haiku)

## Setup

### 1. Clone and Build

```bash
git clone <repo-url>
cd VoiceTranscriber
```

**Option A — Swift Package Manager (command line):**
```bash
swift build
swift run VoiceTranscriber
```

**Option B — Xcode:**

If you have [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed:
```bash
xcodegen generate
open VoiceTranscriber.xcodeproj
```

Or open `Package.swift` directly in Xcode — it will resolve dependencies automatically.

### 2. Configure API Keys

On first launch, the Settings window opens automatically. Enter your API keys:

- **OpenAI API Key** — Get one at [platform.openai.com](https://platform.openai.com/api-keys)
- **Anthropic API Key** — Get one at [console.anthropic.com](https://console.anthropic.com/)

Keys are stored securely in the macOS Keychain.

Alternatively, set environment variables before launching:
```bash
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
```

### 3. Grant Permissions

On first run, macOS will prompt for:
- **Microphone access** — Required for audio recording
- **Accessibility access** — Required for global hotkey listening and text injection

Go to **System Settings > Privacy & Security** to grant these if not prompted.

## Usage

1. **Hold Fn** (or your configured hotkey) to start recording
2. **Speak naturally** — a floating window shows your waveform in real-time
3. **Release Fn** to stop recording and begin processing
4. Your cleaned text is automatically typed into the active text field
5. View past transcripts via the menu bar icon > **Transcript History**

### Hotkey Configuration

Open **Settings > Hotkey** to rebind. Supported options:
- Single keys (Fn, F5, etc.)
- Modifier combinations (⌥Space, ⌃⇧R, ⌘Shift+T, etc.)

### Cleanup Behavior

The Claude cleanup pass:
- Removes filler words: "um", "uh", "like", "you know"
- Resolves self-corrections: "go to the store, no wait, the park" → "go to the park"
- Fixes stuttering: "I-I-I think" → "I think"
- Detects numbered lists and formats them
- Preserves your natural tone and contractions

## Project Structure

```
VoiceTranscriber/
├── Package.swift                          # SPM dependencies (GRDB)
├── project.yml                            # XcodeGen project spec
├── VoiceTranscriber/
│   ├── App/
│   │   └── VoiceTranscriberApp.swift      # Entry point + AppState orchestrator
│   ├── Audio/
│   │   ├── AudioRecorder.swift            # AVAudioEngine recording + level sampling
│   │   └── AudioLevelMonitor.swift        # Smoothed levels for waveform UI
│   ├── API/
│   │   ├── WhisperClient.swift            # OpenAI Whisper API client
│   │   └── ClaudeClient.swift             # Anthropic Claude API client
│   ├── Database/
│   │   └── TranscriptDatabase.swift       # GRDB SQLite storage
│   ├── UI/
│   │   ├── MenuBarView.swift              # Menu bar extra view
│   │   ├── RecordingWindow.swift          # Floating waveform overlay
│   │   ├── TranscriptHistoryView.swift    # History browser with search
│   │   └── SettingsView.swift             # API keys, hotkey, preferences
│   ├── Hotkey/
│   │   └── HotKeyManager.swift            # Global hotkey via Quartz Event Services
│   ├── Models/
│   │   └── Transcript.swift               # Transcript data model
│   └── Utils/
│       ├── TextInjection.swift            # AX API / pasteboard text injection
│       └── ConfigManager.swift            # Keychain + UserDefaults config
├── .env.example                           # API key template
└── .gitignore
```

## Architecture

The app follows a centralized state pattern:

1. **HotKeyManager** listens for the global hotkey via Quartz Event Services
2. **AppState** (the orchestrator) coordinates the full pipeline:
   - Starts **AudioRecorder** (AVAudioEngine) and shows the **RecordingOverlayView**
   - On release, stops recording and sends audio to **WhisperClient**
   - Passes raw transcription to **ClaudeClient** for cleanup
   - Saves the result to **TranscriptDatabase** (GRDB/SQLite)
   - Uses **TextInjector** to type the cleaned text into the active app
3. **MenuBarExtra** provides the persistent UI with quick access to history and settings

All API calls are async/await and non-blocking. The UI stays responsive throughout.

## Dependencies

| Package | Purpose |
|---------|---------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite database for transcript history |

All other functionality uses native frameworks: AVFoundation, AppKit, SwiftUI, Security (Keychain), Quartz Event Services.

## Troubleshooting

**Hotkey not working:**
- Ensure Accessibility permission is granted in System Settings
- Some keys (like Fn) may behave differently on external keyboards

**No text injection:**
- Ensure Accessibility permission is granted
- The target app must have a focused text field
- Falls back to clipboard paste (Cmd+V) if direct injection fails

**API errors:**
- Verify your API keys are correct in Settings
- Check your OpenAI/Anthropic account has sufficient credits
- Ensure network connectivity

## License

MIT
