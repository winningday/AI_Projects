---
type: task-list
scope: VoiceTranscriber-Windows
purpose: Active and planned tasks
last_updated: 2026-03-16
---

## In Progress

## Up Next
- [ ] Test build on Windows machine with .NET 8 SDK
- [ ] Create app icon (.ico file)
- [ ] Add Windows installer (Inno Setup or WiX)
- [ ] Implement UI Automation-based text field reading for CorrectionTracker
- [ ] Add launch-at-startup via Windows Registry
- [ ] Test with various audio input devices

## Done (Recent)
- [x] Initial Windows port — full app created (2026-03-16)
- [x] Core services: AudioRecorder, WhisperClient, ClaudeClient, HotKeyManager, TextInjector
- [x] Data layer: TranscriptDatabase, ConfigManager, CorrectionTracker
- [x] Full WPF UI: 6 navigation tabs + recording overlay + onboarding + system tray
- [x] Build scripts (batch + PowerShell)
- [x] Project documentation

## Backlog
- [ ] Auto-update mechanism
- [ ] Multiple microphone selection in settings
- [ ] Audio format options (WAV vs compressed)
- [ ] Keyboard shortcut for opening main window
- [ ] Toast notifications for transcription completion
- [ ] Dark/light theme toggle
- [ ] Import/export settings
- [ ] Backup/restore transcripts
