"""
pipeline/stage4_subtitles.py — Stage 4: Subtitle generation & export.

Takes the translated TranscriptSegments (with output-timeline timestamps
already adjusted by the EDL engine in Stage 2) and writes:

  1. An SRT file  — for external players and further editing
  2. An ASS file  — for FFmpeg burn-in (richer styling, proper CJK support)

Also exports the raw Chinese + English bilingual transcript as plain text
for human review.

Key considerations:
  - Subtitle timing has already been adjusted for speed changes in Stage 2.
    This module only formats and writes — it does not adjust timing.
  - Long English translations are word-wrapped to fit within the main
    window width without overlapping the PiP panels.
  - Consecutive subtitle segments with < 0.3s gap are merged to avoid
    rapid flicker.
"""

from __future__ import annotations

import logging
import textwrap
from pathlib import Path

from models.segment import TranscriptSegment

log = logging.getLogger(__name__)

# Maximum characters per subtitle line before wrapping
MAX_LINE_LENGTH = 72

# Minimum display duration for any subtitle (seconds)
MIN_DISPLAY_SEC = 1.0

# Gap threshold for merging consecutive subtitles (seconds)
MERGE_GAP_SEC = 0.3


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def generate_subtitles(
    segments: list[TranscriptSegment],
    output_dir: str,
    project_name: str = "watercolor_class",
) -> dict[str, str]:
    """
    Write subtitle and transcript files.

    Returns a dict of {"srt": path, "ass": path, "transcript": path}.
    """
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)

    # Filter to segments with English text on the output timeline
    displayable = [
        seg for seg in segments
        if seg.english_text and seg.english_text.strip()
    ]

    if not displayable:
        log.warning("No translated subtitle segments found — subtitle files will be empty.")

    # Merge near-consecutive segments
    merged = _merge_close_segments(displayable)

    # Enforce minimum display duration
    merged = _enforce_min_duration(merged)

    paths: dict[str, str] = {}

    srt_path = str(out / f"{project_name}.srt")
    _write_srt(merged, srt_path)
    paths["srt"] = srt_path
    log.info(f"SRT written: {srt_path} ({len(merged)} entries)")

    ass_path = str(out / f"{project_name}.ass")
    _write_ass(merged, ass_path, project_name)
    paths["ass"] = ass_path
    log.info(f"ASS written: {ass_path}")

    transcript_path = str(out / f"{project_name}_transcript.txt")
    _write_transcript(segments, transcript_path)
    paths["transcript"] = transcript_path
    log.info(f"Transcript written: {transcript_path}")

    return paths


# ---------------------------------------------------------------------------
# SRT writer
# ---------------------------------------------------------------------------

def _write_srt(segments: list[TranscriptSegment], path: str) -> None:
    lines: list[str] = []
    for i, seg in enumerate(segments, start=1):
        start = _format_srt_time(seg.start_sec)
        end = _format_srt_time(seg.end_sec)
        text = _wrap_text(seg.english_text or "", MAX_LINE_LENGTH)
        lines.append(f"{i}\n{start} --> {end}\n{text}\n")

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def _format_srt_time(seconds: float) -> str:
    """Format seconds as SRT timestamp: HH:MM:SS,mmm"""
    seconds = max(0.0, seconds)
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int(round((seconds % 1) * 1000))
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


# ---------------------------------------------------------------------------
# ASS writer (richer styling for FFmpeg burn-in)
# ---------------------------------------------------------------------------

_ASS_HEADER = """\
[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
ScaledBorderAndShadow: yes
YCbCr Matrix: None

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,28,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,1,0,0,0,100,100,0,0,1,2,1,2,20,20,40,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""


def _write_ass(segments: list[TranscriptSegment], path: str, project_name: str) -> None:
    dialogue_lines: list[str] = []
    for seg in segments:
        start = _format_ass_time(seg.start_sec)
        end = _format_ass_time(seg.end_sec)
        text = _wrap_text_ass(seg.english_text or "", MAX_LINE_LENGTH)
        dialogue_lines.append(
            f"Dialogue: 0,{start},{end},Default,,0,0,0,,{text}"
        )

    with open(path, "w", encoding="utf-8") as f:
        f.write(_ASS_HEADER)
        f.write("\n".join(dialogue_lines))
        f.write("\n")


def _format_ass_time(seconds: float) -> str:
    """Format seconds as ASS timestamp: H:MM:SS.cc"""
    seconds = max(0.0, seconds)
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    cs = int(round((seconds % 1) * 100))  # centiseconds
    return f"{h}:{m:02d}:{s:02d}.{cs:02d}"


def _wrap_text_ass(text: str, max_len: int) -> str:
    """Wrap text using ASS line break tag \\N."""
    lines = textwrap.wrap(text, width=max_len)
    return r"\N".join(lines)


# ---------------------------------------------------------------------------
# Plain transcript writer
# ---------------------------------------------------------------------------

def _write_transcript(segments: list[TranscriptSegment], path: str) -> None:
    """
    Write a bilingual (Chinese + English) plain text transcript.
    Includes timestamps, content labels, and technique tags.
    """
    lines: list[str] = []
    lines.append("WATERCOLOR CLASS — BILINGUAL TRANSCRIPT")
    lines.append("=" * 60)
    lines.append("")

    for seg in segments:
        t_start = _format_timestamp(seg.start_sec)
        t_end = _format_timestamp(seg.end_sec)
        label = seg.content_label.value if seg.content_label else "UNKNOWN"
        tag = f"  [{seg.technique_tag}]" if seg.technique_tag else ""

        lines.append(f"[{t_start} → {t_end}] {label}{tag}")
        lines.append(f"  ZH: {seg.chinese_text}")
        if seg.english_text:
            lines.append(f"  EN: {seg.english_text}")
        lines.append("")

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def _format_timestamp(seconds: float) -> str:
    """Format seconds as MM:SS."""
    seconds = max(0.0, seconds)
    m = int(seconds // 60)
    s = int(seconds % 60)
    return f"{m:02d}:{s:02d}"


# ---------------------------------------------------------------------------
# Post-processing helpers
# ---------------------------------------------------------------------------

def _merge_close_segments(
    segments: list[TranscriptSegment],
) -> list[TranscriptSegment]:
    """
    Merge consecutive segments with < MERGE_GAP_SEC gap to avoid flicker.
    The merged segment gets the combined English text.
    """
    if not segments:
        return segments

    import copy
    merged: list[TranscriptSegment] = [copy.copy(segments[0])]

    for seg in segments[1:]:
        last = merged[-1]
        gap = seg.start_sec - last.end_sec
        if gap < MERGE_GAP_SEC:
            # Extend the last segment and append text
            last.end_sec = seg.end_sec
            last.english_text = (last.english_text or "") + " " + (seg.english_text or "")
            last.english_text = last.english_text.strip()
        else:
            merged.append(copy.copy(seg))

    return merged


def _enforce_min_duration(
    segments: list[TranscriptSegment],
) -> list[TranscriptSegment]:
    """Ensure every subtitle displays for at least MIN_DISPLAY_SEC seconds."""
    import copy
    result = []
    for seg in segments:
        s = copy.copy(seg)
        if s.end_sec - s.start_sec < MIN_DISPLAY_SEC:
            s.end_sec = s.start_sec + MIN_DISPLAY_SEC
        result.append(s)
    return result


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _wrap_text(text: str, max_len: int) -> str:
    """Wrap text at word boundaries for SRT."""
    return "\n".join(textwrap.wrap(text, width=max_len))
