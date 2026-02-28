"""
Configuration for the AI Video Editing Pipeline.

API keys are read from environment variables.
Override defaults via CLI flags or by editing this file.
"""

import os

# ── API Configuration ──────────────────────────────────────────────────────────
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
CLAUDE_MODEL = "claude-opus-4-6"

# ── Whisper Configuration ──────────────────────────────────────────────────────
WHISPER_MODEL_FAST = "base"
WHISPER_MODEL_ACCURACY = "large-v3"

# ── Frame Sampling ─────────────────────────────────────────────────────────────
FRAME_INTERVAL_NORMAL = 3.0          # seconds between frames (normal)
FRAME_INTERVAL_HIGH_MOTION = 1.0     # seconds between frames (scene changes)
SCENE_CHANGE_THRESHOLD = 0.3         # ffmpeg scene-detect threshold (0-1, lower = more sensitive)
FRAMES_DIR = "frames"
FRAME_JPEG_QUALITY = 85              # JPEG quality for extracted frames

# ── Vision Analysis ────────────────────────────────────────────────────────────
VISION_BATCH_SIZE = 20               # max frames per Claude API call
VISION_MAX_RETRIES = 5               # retries on rate limit
VISION_RETRY_BASE_DELAY = 2.0        # exponential backoff base (seconds)
VISION_MAX_IMAGE_SIZE = (1568, 1568) # max dimensions sent to Claude (resize if larger)

# ── Edit Decision Thresholds ───────────────────────────────────────────────────
PAUSE_THRESHOLD = 0.8                # seconds of silence before flagging dead air
MIN_CUT_DURATION = 0.3               # skip cuts shorter than this (artifact risk)
CROSSFADE_DURATION = 0.05            # audio crossfade on each cut (seconds)
STATIC_SCREEN_THRESHOLD = 5.0        # seconds of unchanged screen → speed up
DEFAULT_SPEEDUP_FACTOR = 1.5         # default speed multiplier for flagged segments
MAX_SPEEDUP_FACTOR = 2.0             # maximum speed multiplier
HOOK_WINDOW = 10.0                   # first N seconds reserved for hook
RE_ENGAGE_INTERVAL = (60, 90)        # pattern interrupt window (seconds)

# ── Export Settings ────────────────────────────────────────────────────────────
EXPORT_VIDEO_CODEC = "libx264"
EXPORT_AUDIO_CODEC = "aac"
EXPORT_AUDIO_BITRATE = "192k"
EXPORT_VIDEO_PRESET = "slow"         # x264 preset (slow = better quality)
EXPORT_CRF = 18                      # constant rate factor (lower = better, 18 is visually lossless)
EXPORT_RESOLUTION = "1920:1080"
EXPORT_PIXEL_FORMAT = "yuv420p"
SHORT_MAX_DURATION = 60              # max seconds for YouTube Short candidate
SHORT_RESOLUTION = "1080:1920"       # 9:16 vertical

# ── Output ─────────────────────────────────────────────────────────────────────
OUTPUT_DIR = "output"

# ── Logging ────────────────────────────────────────────────────────────────────
LOG_FILE = "pipeline.log"
LOG_LEVEL = "INFO"
