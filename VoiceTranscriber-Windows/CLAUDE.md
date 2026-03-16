---
type: config
scope: VoiceTranscriber-Windows
purpose: Project-specific rules and context for Claude Code
last_updated: 2026-03-16
---

# CLAUDE.md — Verbalize for Windows

## Project Overview

Windows port of the Verbalize macOS app. Push-to-talk voice transcription with AI cleanup.

## Stack

- **Language**: C# 12
- **Framework**: WPF on .NET 8
- **Audio**: NAudio 2.2
- **Database**: Microsoft.Data.Sqlite 8.0
- **System tray**: WinForms NotifyIcon (via UseWindowsForms)
- **Hotkey**: Win32 low-level keyboard hook (SetWindowsHookEx)
- **Text injection**: Win32 SendInput (Ctrl+V simulation)
- **APIs**: OpenAI Whisper, Anthropic Claude

## Build Commands

```powershell
# Build
dotnet build Verbalize\Verbalize.csproj -c Release

# Run
dotnet run --project Verbalize\Verbalize.csproj

# Publish self-contained
.\build.ps1 -Publish

# Single-file executable
.\build.ps1 -Publish -SingleFile
```

## Architecture

- `Services/AppState.cs` — Singleton orchestrator, coordinates all services
- `Services/AudioRecorder.cs` — NAudio WaveInEvent recording (16kHz mono)
- `Services/WhisperClient.cs` — OpenAI transcription API
- `Services/ClaudeClient.cs` — Anthropic cleanup API
- `Services/HotKeyManager.cs` — Global keyboard hook via SetWindowsHookEx
- `Services/TextInjector.cs` — Clipboard + SendInput for Ctrl+V
- `Services/ConfigManager.cs` — JSON settings in %LOCALAPPDATA%\Verbalize\
- `Services/TranscriptDatabase.cs` — SQLite transcript storage
- `Services/CorrectionTracker.cs` — Self-learning word corrections

## Key Differences from macOS

- Default hotkey is F8 (no Fn key on Windows in same way)
- Uses Win32 P/Invoke instead of macOS accessibility APIs
- Settings stored in JSON file instead of UserDefaults
- System tray instead of menu bar
- No haptic feedback (Windows doesn't have trackpad haptics)
- WinForms NotifyIcon for tray (most reliable approach)

## Patterns

- All services are singletons via AppState.Instance
- INotifyPropertyChanged for WPF data binding
- Async/await for API calls
- Low-level Win32 hooks via P/Invoke for global hotkey

## Important Notes

- Cannot build on Linux — requires Windows with .NET 8 SDK
- Keyboard hook requires the app's message pump to be running
- SendInput requires the app to not be running in a sandboxed context
- Admin elevation may be needed for hotkey capture in some scenarios
