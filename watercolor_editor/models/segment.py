"""
models/segment.py — Core data structures for analysis results.

Every pipeline stage produces or consumes these objects.
Using dataclasses keeps things explicit and serialisable to JSON.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field, asdict
from enum import Enum
from typing import Optional


# ---------------------------------------------------------------------------
# Enumerations
# ---------------------------------------------------------------------------

class AngleID(str, Enum):
    """Which physical camera the segment originates from."""
    A = "a"   # Primary painting view
    B = "b"   # Backup painting view
    C = "c"   # Dedicated palette camera


class ContentLabel(str, Enum):
    """Audio content classification result from Stage 1C."""
    INSTRUCTION = "INSTRUCTION"   # Technique, color mixing, compositional advice
    TRANSITION  = "TRANSITION"    # Between-topic phrasing, checking understanding
    BANTER      = "BANTER"        # Off-topic conversation, small talk, jokes
    SILENCE     = "SILENCE"       # Filler, pause, no speech


class SpeedTier(str, Enum):
    """Speed multiplier tier applied by Stage 1B."""
    ACTIVE  = "active"   # 1.0x  — active brushwork / new technique
    SLOW    = "slow"     # 1.5x  — deliberate application, mixing
    IDLE    = "idle"     # 2.5x  — waiting, drying, observing
    CUT     = "cut"      # dead zone — segment removed entirely


# ---------------------------------------------------------------------------
# Raw analysis results — one per analysis stage
# ---------------------------------------------------------------------------

@dataclass
class MotionResult:
    """Output from Stage 1B motion analysis for a single frame or window."""
    timestamp_sec: float
    motion_score: float         # Mean pixel delta in canvas ROI (0–255)
    speed_tier: SpeedTier
    is_dead_zone: bool = False  # True if part of a >5s no-motion stretch


@dataclass
class ObstructionResult:
    """Output from Stage 1A vision analysis for a single frame."""
    timestamp_sec: float
    angle: AngleID
    canvas_visibility: float    # 0.0–1.0 fraction of canvas ROI that is visible
    is_obstructed: bool = False # True when visibility < threshold


@dataclass
class TranscriptWord:
    """A single word with timing, as returned by Whisper word-level timestamps."""
    word: str
    start_sec: float
    end_sec: float
    confidence: float = 1.0


@dataclass
class TranscriptSegment:
    """A Whisper-generated transcript segment (sentence/clause level)."""
    segment_id: int
    start_sec: float
    end_sec: float
    chinese_text: str
    words: list[TranscriptWord] = field(default_factory=list)

    # Filled in by Stage 1C classification
    content_label: Optional[ContentLabel] = None
    label_confidence: float = 0.0

    # Filled in by Stage 1C translation
    english_text: Optional[str] = None

    # Technique tag — filled by EDL engine to track novelty
    technique_tag: Optional[str] = None

    @property
    def duration_sec(self) -> float:
        return self.end_sec - self.start_sec

    def to_dict(self) -> dict:
        d = asdict(self)
        # Convert enums to string for JSON serialisation
        if self.content_label:
            d["content_label"] = self.content_label.value
        return d


# ---------------------------------------------------------------------------
# Analysis summary — aggregated per time window
# ---------------------------------------------------------------------------

@dataclass
class AnalysisWindow:
    """
    A short time window (typically 0.5–2s) with aggregated analysis results
    from all Stage 1 pipelines. The EDL engine consumes these.
    """
    start_sec: float
    end_sec: float

    # Vision results
    angle_a_visibility: float = 1.0
    angle_b_visibility: float = 1.0
    preferred_angle: AngleID = AngleID.A

    # Motion results
    motion_score: float = 0.0
    speed_tier: SpeedTier = SpeedTier.ACTIVE
    is_dead_zone: bool = False

    # Audio results
    content_label: Optional[ContentLabel] = None
    transcript_segments: list[TranscriptSegment] = field(default_factory=list)

    @property
    def duration_sec(self) -> float:
        return self.end_sec - self.start_sec

    @property
    def is_banter(self) -> bool:
        return self.content_label == ContentLabel.BANTER

    @property
    def is_instructional(self) -> bool:
        return self.content_label in (
            ContentLabel.INSTRUCTION, ContentLabel.TRANSITION
        )


# ---------------------------------------------------------------------------
# Serialisation helpers
# ---------------------------------------------------------------------------

def save_analysis_windows(windows: list[AnalysisWindow], path: str) -> None:
    """Persist analysis results to JSON so stages can be re-run independently."""
    data = []
    for w in windows:
        d = asdict(w)
        d["preferred_angle"] = w.preferred_angle.value
        d["speed_tier"] = w.speed_tier.value
        if w.content_label:
            d["content_label"] = w.content_label.value
        data.append(d)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def load_analysis_windows(path: str) -> list[AnalysisWindow]:
    """Reload persisted analysis results."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    windows = []
    for d in data:
        d["preferred_angle"] = AngleID(d["preferred_angle"])
        d["speed_tier"] = SpeedTier(d["speed_tier"])
        if d.get("content_label"):
            d["content_label"] = ContentLabel(d["content_label"])
        # Reconstruct nested TranscriptSegment objects
        segs = []
        for s in d.get("transcript_segments", []):
            words = [TranscriptWord(**w) for w in s.pop("words", [])]
            if s.get("content_label"):
                s["content_label"] = ContentLabel(s["content_label"])
            segs.append(TranscriptSegment(**s, words=words))
        d["transcript_segments"] = segs
        windows.append(AnalysisWindow(**d))
    return windows
