"""
config.py — Central configuration for the Watercolor Class Video Editor.

All tunable editorial and technical parameters live here.
Change values here rather than hunting through pipeline code.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# Layout — how the final frame is composed
# ---------------------------------------------------------------------------
@dataclass
class LayoutConfig:
    output_width: int = 1920
    output_height: int = 1080

    # Main painting window (left portion)
    main_width_pct: float = 0.75        # 75% of frame width
    main_height_pct: float = 1.0        # full height

    # Top-right: reference photo
    ref_width_pct: float = 0.25
    ref_height_pct: float = 0.50

    # Bottom-right: palette/color camera
    palette_width_pct: float = 0.25
    palette_height_pct: float = 0.50

    # Subtitle bar at bottom of main window
    subtitle_height_px: int = 80
    subtitle_font_size: int = 26
    subtitle_font_color: str = "white"
    subtitle_box_opacity: float = 0.55   # semi-transparent backing


# ---------------------------------------------------------------------------
# Camera / angle roles — set once per project, not computed
# ---------------------------------------------------------------------------
@dataclass
class CameraConfig:
    # Each value is a path or None if that camera wasn't used
    angle_a_path: Optional[str] = None   # Primary painting view
    angle_b_path: Optional[str] = None   # Backup painting view
    angle_c_path: Optional[str] = None   # Dedicated palette camera
    reference_photo_path: Optional[str] = None   # Static reference image

    # Which angle carries the primary audio track (usually the best mic)
    primary_audio_angle: str = "a"       # "a", "b", or "c"


# ---------------------------------------------------------------------------
# Sync — Stage 0
# ---------------------------------------------------------------------------
@dataclass
class SyncConfig:
    # Duration (seconds) to sample from the start of each recording for
    # cross-correlation alignment. Must include the sync clap.
    alignment_window_sec: float = 30.0

    # Sample rate to use for cross-correlation (lower = faster)
    correlation_sr: int = 16_000

    # Re-check drift alignment every N seconds of source footage
    drift_check_interval_sec: float = 600.0   # every 10 minutes

    # Maximum allowable drift before issuing a warning (seconds)
    max_drift_warning_sec: float = 0.5


# ---------------------------------------------------------------------------
# Vision — Stage 1A
# ---------------------------------------------------------------------------
@dataclass
class VisionConfig:
    # Canvas ROI as fractions of the frame [x, y, width, height]
    # Set manually once per project after inspecting angle_a footage.
    # Default: center-left region, safe starting guess.
    canvas_roi_a: tuple = (0.05, 0.10, 0.65, 0.80)  # (x, y, w, h) fractions
    canvas_roi_b: tuple = (0.05, 0.10, 0.65, 0.80)

    # Fraction of canvas ROI that must be unobstructed to keep angle A.
    # If visibility drops below this, switch to angle B.
    obstruction_threshold: float = 0.55

    # How many consecutive frames of obstruction before we switch angle
    # (prevents flickering on brief hand passes)
    obstruction_min_frames: int = 24    # ~1 second at 24fps

    # MediaPipe confidence thresholds
    hand_detection_confidence: float = 0.7
    hand_tracking_confidence: float = 0.5


# ---------------------------------------------------------------------------
# Motion — Stage 1B
# ---------------------------------------------------------------------------
@dataclass
class MotionConfig:
    # Frame difference thresholds (mean pixel delta, 0–255 scale)
    # These determine which speed tier is applied.
    active_threshold: float = 8.0       # above this → 1.0x (active teaching)
    slow_threshold: float = 4.0         # above this → 1.5x (slow application)
    idle_threshold: float = 1.0         # above this → 2.5x (waiting/drying)
    # below idle_threshold → candidate for dead zone cut

    # Speed multipliers for each tier
    speed_active: float = 1.0
    speed_slow: float = 1.5
    speed_idle: float = 2.5
    speed_max: float = 3.0              # hard ceiling — never exceed this

    # Dead zone: if motion score below idle_threshold for this many seconds, CUT
    dead_zone_min_sec: float = 5.0

    # Minimum duration of a speed segment before applying it
    # (prevents micro-speedups that feel glitchy)
    min_speed_segment_sec: float = 3.0

    # Use frame blending when speed > this multiplier
    blend_above_speed: float = 1.5

    # Rolling window (seconds) for smoothing motion scores
    smoothing_window_sec: float = 1.5


# ---------------------------------------------------------------------------
# Audio / Content Classification — Stage 1C
# ---------------------------------------------------------------------------
@dataclass
class AudioConfig:
    # Whisper model size — "large-v3" for best Mandarin accuracy,
    # "medium" for faster iteration during development
    whisper_model: str = "large-v3"
    whisper_language: str = "zh"        # Chinese (auto-detects Mandarin/Cantonese)
    whisper_word_timestamps: bool = True

    # Claude model for classification and translation
    claude_model: str = "claude-sonnet-4-6"

    # Classification batch size — number of transcript segments sent to Claude
    # at once. Larger = fewer API calls but more tokens per call.
    classification_batch_size: int = 15

    # Content labels the classifier will assign
    label_instruction: str = "INSTRUCTION"
    label_transition: str = "TRANSITION"
    label_banter: str = "BANTER"
    label_silence: str = "SILENCE"

    # Banter handling thresholds
    banter_mute_if_under_sec: float = 10.0  # short banter: mute + speedup
    banter_cut_if_over_sec: float = 10.0    # long banter: cut with title card

    # Speed applied to muted banter segments
    banter_speed_multiplier: float = 3.0

    # Dissolve duration (seconds) when cutting around banter
    banter_cut_dissolve_sec: float = 0.5


# ---------------------------------------------------------------------------
# Edit Decision List — Stage 2
# ---------------------------------------------------------------------------
@dataclass
class EDLConfig:
    # Angle switch transition duration in seconds
    angle_switch_dissolve_sec: float = 0.08    # ~2 frames at 24fps

    # Title card duration when a long banter section is cut
    title_card_duration_sec: float = 2.0

    # Lock speed to 1.0x for this many seconds after a new technique label
    # appears for the first time in the session
    new_technique_lockout_sec: float = 30.0


# ---------------------------------------------------------------------------
# Composition & Render — Stage 3
# ---------------------------------------------------------------------------
@dataclass
class RenderConfig:
    output_fps: int = 30
    output_codec: str = "libx264"
    output_crf: int = 18               # 0=lossless, 23=default, 18=high quality
    output_preset: str = "slow"        # encoding speed vs. file size
    audio_codec: str = "aac"
    audio_bitrate: str = "192k"
    pixel_format: str = "yuv420p"      # broad compatibility

    # Intermediate files go here (auto-cleaned after successful render)
    temp_dir: Path = Path("output/temp")
    final_output_dir: Path = Path("output/final")


# ---------------------------------------------------------------------------
# Master config object — import this everywhere
# ---------------------------------------------------------------------------
@dataclass
class WatercolorEditorConfig:
    layout: LayoutConfig = field(default_factory=LayoutConfig)
    cameras: CameraConfig = field(default_factory=CameraConfig)
    sync: SyncConfig = field(default_factory=SyncConfig)
    vision: VisionConfig = field(default_factory=VisionConfig)
    motion: MotionConfig = field(default_factory=MotionConfig)
    audio: AudioConfig = field(default_factory=AudioConfig)
    edl: EDLConfig = field(default_factory=EDLConfig)
    render: RenderConfig = field(default_factory=RenderConfig)

    # Project label — used in output filenames and title cards
    project_name: str = "watercolor_class"

    # Set True during development to run on first N minutes of footage only
    dev_mode: bool = False
    dev_mode_duration_sec: float = 300.0   # 5 minutes


# Default instance — override fields as needed per project
DEFAULT_CONFIG = WatercolorEditorConfig()
