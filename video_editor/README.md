# AI Video Editing Pipeline

Two-phase AI video editing pipeline for YouTube content creation. Takes raw screen/webcam recordings of educational AI content and produces polished, upload-ready MP4s.

## How It Works

**Phase 1 — Multimodal Analysis** (`analyze_video.py`):
1. Transcribes audio with Whisper (word-level timestamps)
2. Extracts frames at regular intervals + scene changes
3. Sends frames to Claude Vision for visual quality/content analysis
4. Combines transcript + vision data into unified edit decisions

**Phase 2 — Auto Editor** (`apply_edits.py`):
1. Reads the edit notes JSON
2. Executes cuts, speedups, and stitching via ffmpeg
3. Exports final edit, YouTube Short candidate, and upload metadata

**Phase 3 — Review** (`review.py`):
1. Displays the full edit plan with statistics
2. Interactive approve/skip/override for each cut
3. Re-runs the editor with your overrides

## Prerequisites

- Python 3.11+
- ffmpeg (system install)
- `ANTHROPIC_API_KEY` environment variable

## Setup

```bash
pip install -r requirements.txt
export ANTHROPIC_API_KEY="sk-ant-..."
```

## Usage

```bash
# Full pipeline
python analyze_video.py --input raw_video.mp4
python review.py --input raw_video.mp4
python apply_edits.py --input raw_video.mp4

# High-accuracy transcription (uses whisper large-v3)
python analyze_video.py --input raw_video.mp4 --mode accuracy

# Dry run — see the edit plan without writing files
python apply_edits.py --input raw_video.mp4 --dry-run

# Non-interactive review (display only)
python review.py --no-interact

# Reuse existing analysis data
python analyze_video.py --input raw_video.mp4 --skip-transcription --skip-vision
```

## Output

```
output/
├── final_edit.mp4         # Polished, upload-ready video
├── short_candidate.mp4    # 9:16 vertical clip for YouTube Shorts (≤60s)
└── upload_metadata.txt    # Title, description template, tags, thumbnail timestamp
```

## Configuration

Edit `config.py` to adjust:
- Whisper model selection
- Frame sampling intervals and scene-change sensitivity
- Vision batch size and rate limit handling
- Edit thresholds (pause detection, min cut duration, speedup limits)
- Export quality settings (codec, CRF, resolution, bitrate)

## Edit Decision Signals

Every cut in the edit notes includes a `signal` field:
- `audio` — decision based on transcript (filler words, dead air, repeated sentences)
- `visual` — decision based on frame analysis (loading screens, clutter, errors)
- `both` — both audio and visual signals agreed on the cut
