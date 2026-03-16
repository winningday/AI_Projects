---
type: memory-log
scope: VoiceTranscriber-Windows
purpose: Persistent session memory for Claude Code
last_updated: 2026-03-16
---

## 2026-03-16 — Initial Windows Port Created

- **What:** Built complete Windows port of Verbalize (macOS voice transcriber) using C#/WPF/.NET 8
- **Files:** Full project created — 24 files total:
  - Solution: `Verbalize.sln`
  - Project: `Verbalize/Verbalize.csproj`
  - App entry: `App.xaml`, `App.xaml.cs`
  - Models: `Transcript.cs`, `DictionaryEntry.cs`, `WordCorrection.cs`, `StyleTone.cs`
  - Services: `AppState.cs`, `AudioRecorder.cs`, `WhisperClient.cs`, `ClaudeClient.cs`, `HotKeyManager.cs`, `TextInjector.cs`, `ConfigManager.cs`, `TranscriptDatabase.cs`, `CorrectionTracker.cs`
  - Views: `MainWindow.xaml/.cs`, `HomePage.xaml/.cs`, `HistoryPage.xaml/.cs`, `StatsPage.xaml/.cs`, `DictionaryPage.xaml/.cs`, `StylePage.xaml/.cs`, `SettingsPage.xaml/.cs`, `RecordingOverlay.xaml/.cs`, `OnboardingWindow.xaml/.cs`, `SystemTrayManager.cs`
  - Resources: `Theme.xaml`
  - Converters: `BoolToVisibilityConverter.cs`
  - Build: `build.bat`, `build.ps1`
  - Docs: `README.md`, `CLAUDE.md`, `MEMORY.md`, `TODO.md`
- **Decisions:**
  - Used WPF over WinUI 3 for broader Win10 compatibility
  - F8 as default hotkey (Fn key doesn't work same way on Windows)
  - JSON file for settings instead of Windows Registry (more portable)
  - WinForms NotifyIcon for system tray (most reliable)
  - NAudio for audio (industry standard for Windows .NET audio)
  - Low-level keyboard hook (SetWindowsHookEx) for global hotkey capture
  - Win32 SendInput for Ctrl+V text injection
  - Dark theme matching macOS version's aesthetic
- **Gotchas:**
  - Cannot build on Linux — needs Windows + .NET 8 SDK
  - Keyboard hook requires message pump (WPF provides this)
  - System tray uses WinForms interop (UseWindowsForms in csproj)
  - CorrectionTracker simplified — Windows doesn't have easy UI Automation for reading arbitrary text fields from other apps
- **Next:** Test on Windows machine, add .ico icon file, potential installer (WiX/Inno Setup)
