---
type: readme
scope: VoiceTranscriberIOS
purpose: User-facing documentation for Verbalize iOS app
last_updated: 2026-03-16
---

# Verbalize for iOS

Privacy-first voice-to-text iOS app with a custom keyboard extension. Speak instead of type — anywhere on your iPhone.

## Features

- **Custom Keyboard** — Tap the mic button on the Verbalize keyboard to transcribe speech directly into any text field
- **Smart Cleanup** — Claude Haiku cleans up filler words, fixes grammar, and formats text intelligently
- **Self-Learning** — Detects when you edit transcribed text and learns your corrections for next time
- **Custom Dictionary** — Add names, technical terms, and custom words for accurate transcription
- **Translation** — Real-time translation to 20+ languages
- **Style Profiles** — Formal for email, casual for messages, very casual for texting
- **Smart Formatting** — Detects code, URLs, and technical content
- **Transcript History** — Searchable history of all transcriptions with stats

## Architecture

```
VoiceTranscriberIOS/
├── Shared/                    # Shared between app and keyboard extension
│   ├── API/                   # WhisperClient + ClaudeClient
│   ├── Config/                # SharedConfig (App Group UserDefaults)
│   ├── Database/              # TranscriptDatabase (GRDB in App Group container)
│   ├── Models/                # Transcript, StyleModels, WordCorrection
│   └── Utils/                 # AudioRecorderIOS, CorrectionTracker
├── VoiceTranscriberIOS/       # Main iOS app
│   ├── App/                   # App entry point + AppState orchestrator
│   └── Views/                 # All SwiftUI views
├── VerbalizeKeyboard/         # Custom keyboard extension
│   ├── KeyboardViewController # UIInputViewController + transcription pipeline
│   └── KeyboardView           # SwiftUI keyboard layout with mic button
└── project.yml                # XcodeGen project spec
```

## Setup

### Prerequisites
- Xcode 15+
- iOS 16+ device (keyboard extensions require a real device for mic access)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for generating the Xcode project)

### Build Steps

1. **Generate Xcode project:**
   ```bash
   cd VoiceTranscriberIOS
   brew install xcodegen  # if not installed
   xcodegen generate
   ```

2. **Open in Xcode:**
   ```bash
   open VoiceTranscriberIOS.xcodeproj
   ```

3. **Configure signing:**
   - Select both targets (VoiceTranscriberIOS and VerbalizeKeyboard)
   - Set your Development Team
   - Ensure the App Group `group.com.verbalize.ios` is enabled in both targets

4. **Build and run** on your device (not simulator — mic doesn't work in keyboard extensions on simulator)

### Enable the Keyboard

After installing:
1. Go to **Settings > General > Keyboard > Keyboards**
2. Tap **Add New Keyboard...**
3. Select **Verbalize**
4. Tap **Verbalize** > Enable **Allow Full Access** (required for network access to transcription APIs)

## API Keys

The app requires:
- **OpenAI API Key** — for Whisper transcription (`gpt-4o-mini-transcribe` / `whisper-1` fallback)
- **Claude API Key** — for intelligent text cleanup (`claude-haiku-4-5-20251001`)

Enter keys in the main app's Settings tab. They're stored in App Group UserDefaults and shared with the keyboard extension.

## How It Works

### Keyboard Transcription Flow
1. User taps the **blue mic button** on the keyboard
2. Audio records via AVAudioEngine (16kHz mono)
3. Waveform visualization shows recording status
4. User taps **Done** (or mic again) to stop
5. Audio → OpenAI Whisper → raw text
6. Raw text → Claude Haiku → cleaned text (with dictionary, style, corrections)
7. Cleaned text inserted into text field via `textDocumentProxy.insertText()`
8. CorrectionTracker monitors for user edits → learns for next time

### Self-Learning System
- After inserting transcribed text, the keyboard monitors `textDidChange`
- When the user edits the inserted text, word-level diff detects corrections
- Corrections are stored and fed into future Claude prompts
- Corrected words are auto-added to the dictionary

## Tech Stack

- **Swift 5.9** / **SwiftUI** / **UIKit** (keyboard extension)
- **GRDB** (SQLite) — transcript storage in App Group container
- **OpenAI Whisper API** — speech-to-text
- **Anthropic Claude API** — text cleanup + translation
- **App Groups** — shared data between app and keyboard extension
- **AVAudioEngine** — real-time audio recording with level monitoring
