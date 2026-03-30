---
type: config
scope: VoiceTranscriber
purpose: Project-specific rules, workflow documentation, and build commands for Verbalize (macOS)
last_updated: 2026-03-30
---

# VoiceTranscriber (Verbalize) — Project CLAUDE.md

## Build & Run

- **No Swift compiler on dev server.** All changes validated on user's Mac.
- Build: `cd VoiceTranscriber && swift build` (on Mac only)
- Run: `swift run` or open in Xcode and Cmd+R
- Package manager: Swift Package Manager (`Package.swift`)
- Min target: macOS 13.0 (Ventura)

## Architecture — Recording Pipeline

```
User presses hotkey (Fn by default)
  ↓
HotKeyManager detects keyDown → AppState.startRecording()
  ├─ TextInjector.readContextFromActiveField() → captures surrounding text
  ├─ TextInjector.activeAppName() → captures active app name
  ├─ AudioRecorder.startRecording() → AVAudioEngine 16kHz mono
  └─ RecordingWindow shows waveform overlay

User releases hotkey
  ↓
HotKeyManager detects keyUp → AppState.stopRecordingAndProcess()
  ├─ AudioRecorder.stopRecording() → returns (URL, duration)
  └─ processRecording() async:

      IF transcriptionEngine == .claudeAudio:
        ├─ ClaudeAudioClient.transcribeAndClean() → single API call
        │  (audio sent as base64 content block, all settings applied in system prompt)
        └─ Returns (rawText, cleanedText) — both transcription and cleanup done
      ELSE:
        ├─ Step 1: Transcribe with selected engine:
        │  ├─ .whisperMini → WhisperClient (gpt-4o-mini-transcribe)
        │  ├─ .whisperFull → WhisperClient (gpt-4o-transcribe)
        │  ├─ .deepgram → DeepgramClient (Nova-2)
        │  └─ .appleSpeech → AppleSpeechClient (SFSpeechRecognizer)
        │
        ├─ Step 2: Clean transcript:
        │  ├─ IF useAICleanup OR translationEnabled:
        │  │  └─ ClaudeClient.cleanTranscription() with ALL settings
        │  └─ ELSE:
        │     └─ ProgrammaticCleaner.clean() — fast, no API, basic formatting
        │
        └─ Step 3: Save + inject

      ├─ TranscriptDatabase.save(transcript)
      ├─ TextInjector.inject(cleanedText) — prepends space if needed
      └─ CorrectionTracker.startTracking() — self-learning feedback
```

## CRITICAL: Settings That Feed Into the Pipeline

**DO NOT disable or bypass these without understanding what breaks:**

| Setting | Where Used | What It Does |
|---------|-----------|--------------|
| `dictionaryWords` | WhisperClient prompt, DeepgramClient keywords, ClaudeClient prompt, ClaudeAudioClient prompt | Custom words/names for spelling accuracy |
| `styleTone` (per context) | ClaudeClient, ClaudeAudioClient, ProgrammaticCleaner | Formal/Casual/VeryCasual/Excited formatting |
| `contextAwareness` | TextInjector reads active field, passed to Claude | Helps spell names, understand topic |
| `smartFormatting` | ClaudeClient, ClaudeAudioClient | Preserves code formatting (camelCase, etc.) |
| `recentCorrections` | ClaudeClient, ClaudeAudioClient | Self-learning from user edits |
| `translationEnabled` + `targetLanguage` | ClaudeClient, ClaudeAudioClient | **Forces AI cleanup** — programmatic can't translate |
| `autoInjectText` | TextInjector.inject() | Whether to paste into active field |
| `useAICleanup` | Pipeline branching | TRUE = Claude cleanup, FALSE = programmatic |
| `transcriptionEngine` | Pipeline branching | Which STT engine to use |

### Settings Dependencies

- **Translation ON** → forces Claude cleanup regardless of `useAICleanup`
- **Claude Audio engine** → does both transcription and cleanup, uses Claude API key (not OpenAI)
- **Programmatic cleanup** → only handles: capitalization, punctuation, filler removal, stutter fixing. Does NOT handle: smart formatting, translation, dictionary-aware cleanup, context-aware tone
- **Apple Speech** → no dictionary hints support, lower accuracy

## API Key Requirements by Configuration

| Engine | Needs OpenAI Key | Needs Claude Key | Needs Deepgram Key |
|--------|:---:|:---:|:---:|
| Whisper (Mini/Full) + AI Cleanup | Yes | Yes | No |
| Whisper + Programmatic Cleanup | Yes | No | No |
| Claude Direct Audio | No | Yes | No |
| Deepgram + AI Cleanup | No | Yes | Yes |
| Deepgram + Programmatic | No | No | Yes |
| Apple Speech + AI Cleanup | No | Yes | No |
| Apple Speech + Programmatic | No | No | No |

## File Map

See `.context/overview.yaml` for the full file list. Key files:

| File | Purpose |
|------|---------|
| `App/VoiceTranscriberApp.swift` | AppState orchestrator, recording pipeline, all service wiring |
| `API/WhisperClient.swift` | OpenAI Whisper STT (mini + full models) |
| `API/ClaudeClient.swift` | Claude text cleanup (filler removal, formatting, translation) |
| `API/ClaudeAudioClient.swift` | Claude direct audio (transcribe + clean in one call) |
| `API/DeepgramClient.swift` | Deepgram Nova-2 STT |
| `API/AppleSpeechClient.swift` | Apple SFSpeechRecognizer (on-device) |
| `Utils/ProgrammaticCleaner.swift` | Fast deterministic cleanup (no AI) |
| `Utils/ConfigManager.swift` | All settings, API keys, dictionary, corrections |
| `Utils/TextInjection.swift` | Pastes text into active field, reads context |
| `Utils/CorrectionTracker.swift` | Self-learning from user edits |
| `UI/AppSettingsView.swift` | Settings page with all toggles and API key fields |
| `UI/HomeView.swift` | Dashboard with date-grouped transcripts |

## Rules for Claude Code

1. **Always read this file and `.context/overview.yaml` before making changes.**
2. **Never add a setting without wiring it through the full pipeline** — check the pipeline diagram above.
3. **Test all engine paths mentally** — each `TranscriptionEngine` case must handle all settings.
4. **Translation forces AI cleanup** — never break this invariant.
5. **Claude Direct Audio is special** — it does transcription + cleanup in one call, bypasses the separate cleanup step entirely.
6. **ProgrammaticCleaner is a fallback**, not the default. AI cleanup is on by default.
7. **No Swift compiler on dev server** — cannot build or test here.
