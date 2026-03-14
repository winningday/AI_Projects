"""
models/edl.py — Edit Decision List (EDL) data structures.

The EDL is the complete ordered specification of the final edit.
Every rendering decision is encoded here before FFmpeg touches anything.
This separation means you can inspect, tweak, or override the EDL
without re-running the expensive analysis stages.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field, asdict
from enum import Enum
from typing import Optional

from models.segment import AngleID, TranscriptSegment


# ---------------------------------------------------------------------------
# EDL entry types
# ---------------------------------------------------------------------------

class EDLEntryType(str, Enum):
    """What kind of action this EDL entry represents."""
    CLIP        = "clip"        # Normal video segment
    TITLE_CARD  = "title_card"  # Inserted text card (e.g. "10 minutes later")
    DISSOLVE    = "dissolve"    # Cross-dissolve transition between two clips


@dataclass
class EDLEntry:
    """
    A single atomic decision in the Edit Decision List.

    For CLIP entries:
      - source_angle tells us which camera file to read
      - source_in / source_out give the real timestamps in the source file
      - timeline_in / timeline_out are where this lands in the output
      - speed_multiplier compresses or expands playback

    For TITLE_CARD entries:
      - title_text is displayed as a simple full-frame card
      - source fields are unused

    For DISSOLVE entries:
      - duration_sec specifies the overlap
      - source fields are unused (dissolve is between adjacent CLIPs)
    """
    entry_type: EDLEntryType
    timeline_in: float          # seconds in the output timeline
    timeline_out: float         # seconds in the output timeline

    # CLIP fields
    source_angle: Optional[AngleID] = None
    source_in: Optional[float] = None   # seconds in the source file
    source_out: Optional[float] = None

    speed_multiplier: float = 1.0
    audio_on: bool = True               # False = mute this segment

    # TITLE_CARD fields
    title_text: Optional[str] = None
    title_subtext: Optional[str] = None  # smaller secondary line

    # Subtitle segments that fall within this clip's timeline window
    subtitles: list[TranscriptSegment] = field(default_factory=list)

    # Editorial note — why was this decision made? Useful for review UI.
    reason: str = ""

    @property
    def duration_sec(self) -> float:
        return self.timeline_out - self.timeline_in

    @property
    def source_duration_sec(self) -> Optional[float]:
        if self.source_in is not None and self.source_out is not None:
            return self.source_out - self.source_in
        return None

    def to_dict(self) -> dict:
        d = asdict(self)
        d["entry_type"] = self.entry_type.value
        if self.source_angle:
            d["source_angle"] = self.source_angle.value
        return d


@dataclass
class EditDecisionList:
    """
    The complete EDL for one session.

    Entries are ordered by timeline_in. Gaps between entries should not
    exist — the EDL engine is responsible for ensuring continuity.
    """
    project_name: str
    total_source_duration_sec: float    # original footage length (before editing)
    entries: list[EDLEntry] = field(default_factory=list)

    # Running stats — populated after build()
    total_output_duration_sec: float = 0.0
    clips_cut: int = 0                  # dead zones removed
    banter_segments_cut: int = 0
    banter_segments_muted: int = 0
    angle_switches: int = 0
    speed_ramp_segments: int = 0

    def append(self, entry: EDLEntry) -> None:
        self.entries.append(entry)

    def total_timeline_duration(self) -> float:
        if not self.entries:
            return 0.0
        return self.entries[-1].timeline_out

    def compression_ratio(self) -> float:
        """How much shorter the output is vs. raw source. 1.0 = no compression."""
        if self.total_source_duration_sec == 0:
            return 1.0
        return self.total_timeline_duration() / self.total_source_duration_sec

    def summary(self) -> str:
        src_min = self.total_source_duration_sec / 60
        out_min = self.total_timeline_duration() / 60
        return (
            f"Project: {self.project_name}\n"
            f"Source duration:  {src_min:.1f} min\n"
            f"Output duration:  {out_min:.1f} min  "
            f"({self.compression_ratio():.0%} of original)\n"
            f"Dead zones cut:   {self.clips_cut}\n"
            f"Banter cut:       {self.banter_segments_cut}\n"
            f"Banter muted:     {self.banter_segments_muted}\n"
            f"Angle switches:   {self.angle_switches}\n"
            f"Speed ramps:      {self.speed_ramp_segments}\n"
            f"Total entries:    {len(self.entries)}"
        )

    def save(self, path: str) -> None:
        data = {
            "project_name": self.project_name,
            "total_source_duration_sec": self.total_source_duration_sec,
            "total_output_duration_sec": self.total_output_duration_sec,
            "clips_cut": self.clips_cut,
            "banter_segments_cut": self.banter_segments_cut,
            "banter_segments_muted": self.banter_segments_muted,
            "angle_switches": self.angle_switches,
            "speed_ramp_segments": self.speed_ramp_segments,
            "entries": [e.to_dict() for e in self.entries],
        }
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    @classmethod
    def load(cls, path: str) -> EditDecisionList:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        entries = []
        for e in data.pop("entries", []):
            e["entry_type"] = EDLEntryType(e["entry_type"])
            if e.get("source_angle"):
                e["source_angle"] = AngleID(e["source_angle"])
            # Subtitles are informational in loaded EDL; skip full reconstruction
            e.pop("subtitles", None)
            e["subtitles"] = []
            entries.append(EDLEntry(**e))
        edl = cls(**data)
        edl.entries = entries
        return edl
