---
type: readme
scope: VoiceTranscriber-Windows
purpose: User-facing documentation for the Verbalize Windows app
last_updated: 2026-03-16
---

# Verbalize for Windows

Push-to-talk voice transcription with AI cleanup. Hold a hotkey, speak, release — your words appear as clean text in any app.

## Features

- **Push-to-talk recording** — Hold F8 (or custom hotkey) to record, release to process
- **Real-time waveform** — Floating overlay shows audio levels during recording
- **Whisper transcription** — Uses OpenAI's latest transcription models
- **Claude AI cleanup** — Removes filler words, fixes stuttering, applies smart formatting
- **Auto-paste** — Cleaned text is automatically pasted into the active text field
- **Context awareness** — Detects active app and adjusts tone (Slack = professional, WhatsApp = casual)
- **20 language translation** — Real-time translation to/from 20 languages
- **Custom dictionary** — Add words to improve transcription accuracy
- **Self-learning corrections** — Tracks your edits and learns from them
- **4 style profiles** — Formal, Casual, Very Casual, Excited
- **Productivity stats** — WPM tracking, time saved calculations, weekly charts
- **System tray** — Runs in background, accessible from tray icon
- **Transcript history** — Searchable database of all past transcriptions

## Requirements

- Windows 10 or Windows 11
- .NET 8.0 Runtime (or use self-contained build)
- Microphone
- OpenAI API key (required)
- Anthropic API key (optional, for AI cleanup)

## Quick Start

### Option 1: Run from Source

```powershell
# Clone and navigate
cd VoiceTranscriber-Windows

# Build and run
dotnet run --project Verbalize\Verbalize.csproj
```

### Option 2: Build Distributable

```powershell
# Using PowerShell script
.\build.ps1 -Publish

# Or for single-file executable
.\build.ps1 -Publish -SingleFile

# Using batch file
build.bat Release --publish
```

The published app will be in `publish\Verbalize\`.

## Setup

On first launch, the onboarding wizard will guide you through:

1. **Microphone access** — Windows will prompt for permission on first recording
2. **API keys** — Enter your OpenAI key (required) and Anthropic key (optional)

## Usage

1. **Press and hold F8** (or your configured hotkey) to start recording
2. A floating overlay appears showing waveform and duration
3. **Release the key** to stop recording
4. Your speech is transcribed, cleaned by AI, and pasted into the active text field

### Hotkey

- Default: **F8**
- Change in Settings > Push-to-Talk Hotkey > Change Hotkey
- Supports single keys and modifier combinations (Ctrl+Shift+R, Alt+Space, etc.)

### System Tray

- The app minimizes to the system tray when closed (configurable)
- Double-click the tray icon to open the main window
- Right-click for quick actions (translation toggle, quit)

## Architecture

```
Verbalize/
├── Services/           # Core business logic
│   ├── AppState.cs         # Central orchestrator
│   ├── AudioRecorder.cs    # NAudio microphone recording
│   ├── WhisperClient.cs    # OpenAI Whisper API
│   ├── ClaudeClient.cs     # Anthropic Claude API
│   ├── HotKeyManager.cs    # Global keyboard hook
│   ├── TextInjector.cs     # Clipboard + Ctrl+V injection
│   ├── ConfigManager.cs    # Settings persistence (JSON)
│   ├── TranscriptDatabase.cs  # SQLite via Microsoft.Data.Sqlite
│   └── CorrectionTracker.cs   # Self-learning word corrections
├── Models/             # Data types
│   ├── Transcript.cs
│   ├── DictionaryEntry.cs
│   ├── WordCorrection.cs
│   └── StyleTone.cs
├── Views/              # WPF UI
│   ├── MainWindow.xaml     # Main app with sidebar navigation
│   ├── HomePage.xaml       # Dashboard with quick stats
│   ├── HistoryPage.xaml    # Searchable transcript list
│   ├── StatsPage.xaml      # Productivity analytics
│   ├── DictionaryPage.xaml # Custom word management
│   ├── StylePage.xaml      # Per-context tone settings
│   ├── SettingsPage.xaml   # All settings
│   ├── RecordingOverlay.xaml   # Floating recording indicator
│   ├── OnboardingWindow.xaml   # First-run setup wizard
│   └── SystemTrayManager.cs   # Tray icon + context menu
├── Converters/         # WPF value converters
├── Resources/          # Theme and styles
│   └── Theme.xaml
├── build.bat           # Windows batch build script
└── build.ps1           # PowerShell build script
```

## Data Storage

All data is stored locally in `%LOCALAPPDATA%\Verbalize\`:

- `settings.json` — All configuration (API keys stored with base64 obfuscation)
- `transcripts.sqlite` — Transcript database

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| F8 (default) | Hold to record, release to transcribe |
| Esc | Cancel active recording |

## Differences from macOS Version

| Feature | macOS | Windows |
|---------|-------|---------|
| Framework | SwiftUI | WPF (.NET 8) |
| Audio | AVAudioEngine | NAudio |
| Database | GRDB (SQLite) | Microsoft.Data.Sqlite |
| Hotkey | CGEvent tap + NSEvent | Low-level keyboard hook |
| Text injection | Cmd+V | Ctrl+V |
| System integration | Menu bar | System tray |
| Settings storage | UserDefaults | JSON file |
| Fn key support | Yes (macOS-specific) | No (uses F8 default) |
| Haptic feedback | Yes (trackpad) | No (not available) |

## Troubleshooting

**Hotkey not working?**
- Make sure no other app is using the same hotkey
- Try running Verbalize as administrator

**No audio recording?**
- Check Windows Settings > Privacy > Microphone
- Make sure your microphone is set as default recording device

**Transcription fails?**
- Verify your OpenAI API key in Settings
- Check your internet connection
- Ensure you have API credits remaining
