"""
pipeline/stage2_edl.py — Stage 2: Edit Decision List engine.

Consumes all Stage 1 analysis results and produces a fully-specified EDL.
This is the editorial brain of the system.

Rule priority order (higher = more important, applied first):
  1. Dead zone → CUT completely
  2. BANTER (long) → CUT with title card
  3. BANTER (short) → MUTE + 3x speed
  4. New technique detected → LOCK to 1.0x (override motion tier)
  5. Obstruction on A → SWITCH to angle B
  6. Motion tier → apply speed multiplier
  7. Default → 1.0x, angle A, audio on

The EDL is then post-processed to:
  - Insert DISSOLVE entries at every angle switch
  - Ensure no gaps in the timeline
  - Recalculate subtitle timestamps to account for speed changes
"""

from __future__ import annotations

import logging
from collections import defaultdict
from typing import Optional

from config import WatercolorEditorConfig
from models.edl import EditDecisionList, EDLEntry, EDLEntryType
from models.segment import (
    AngleID, AnalysisWindow, ContentLabel, SpeedTier, TranscriptSegment
)
from pipeline.stage1b_motion import tier_to_multiplier

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def build_edl(
    config: WatercolorEditorConfig,
    windows: list[AnalysisWindow],
    transcripts: list[TranscriptSegment],
    source_duration_sec: float,
) -> EditDecisionList:
    """
    Build the complete Edit Decision List from analysis windows and transcripts.

    windows: list of AnalysisWindow objects (from Stages 1A + 1B aggregated)
    transcripts: list of TranscriptSegment objects (from Stage 1C)
    source_duration_sec: total length of the source footage (angle A)
    """
    cfg = config
    edl = EditDecisionList(
        project_name=cfg.project_name,
        total_source_duration_sec=source_duration_sec,
    )

    # Index transcripts by start time for fast lookup
    transcript_index = _build_transcript_index(transcripts)

    # Track which technique tags have been seen (for novelty detection)
    seen_techniques: set[str] = set()

    # EDL state
    timeline_cursor = 0.0       # current position in the output timeline
    source_cursor = 0.0         # current position in the source (angle A) timeline
    current_angle = AngleID.A
    clip_buffer: list[AnalysisWindow] = []  # windows being accumulated into a clip

    def flush_clip_buffer():
        """Emit an EDLEntry for the accumulated windows in clip_buffer."""
        nonlocal timeline_cursor, source_cursor, current_angle
        if not clip_buffer:
            return

        # Determine speed for this clip from the dominant tier
        dominant_tier = _dominant_tier(clip_buffer)
        speed = tier_to_multiplier(dominant_tier, cfg.motion)
        speed = min(speed, cfg.motion.speed_max)

        source_in = clip_buffer[0].start_sec
        source_out = clip_buffer[-1].end_sec
        source_dur = source_out - source_in
        output_dur = source_dur / speed

        # Collect subtitles that fall within this source window, adjusted for speed
        clip_subs = _collect_subtitles(
            transcript_index, source_in, source_out,
            timeline_cursor, speed
        )

        entry = EDLEntry(
            entry_type=EDLEntryType.CLIP,
            timeline_in=timeline_cursor,
            timeline_out=timeline_cursor + output_dur,
            source_angle=current_angle,
            source_in=source_in,
            source_out=source_out,
            speed_multiplier=speed,
            audio_on=True,
            subtitles=clip_subs,
            reason=f"tier={dominant_tier.value}, angle={current_angle.value}",
        )
        edl.append(entry)

        if speed != 1.0:
            edl.speed_ramp_segments += 1

        timeline_cursor += output_dur
        clip_buffer.clear()

    # ---------------------------------------------------------------------------
    # Main pass over analysis windows
    # ---------------------------------------------------------------------------
    for win in windows:
        source_cursor = win.start_sec

        # --- Rule 1: Dead zone → CUT ---
        if win.is_dead_zone:
            flush_clip_buffer()
            edl.clips_cut += 1
            log.debug(f"CUT dead zone at t={win.start_sec:.1f}s")
            continue

        # --- Rule 2 & 3: Banter handling ---
        if win.content_label == ContentLabel.BANTER:
            flush_clip_buffer()
            banter_dur = win.duration_sec

            if banter_dur >= cfg.audio.banter_cut_if_over_sec:
                # Long banter → cut + title card
                _emit_title_card(edl, timeline_cursor, cfg.edl.title_card_duration_sec)
                timeline_cursor += cfg.edl.title_card_duration_sec
                edl.banter_segments_cut += 1
                log.debug(f"CUT long banter at t={win.start_sec:.1f}s ({banter_dur:.1f}s)")
            else:
                # Short banter → mute + speed up
                source_in = win.start_sec
                source_out = win.end_sec
                source_dur = source_out - source_in
                speed = cfg.audio.banter_speed_multiplier
                output_dur = source_dur / speed

                edl.append(EDLEntry(
                    entry_type=EDLEntryType.CLIP,
                    timeline_in=timeline_cursor,
                    timeline_out=timeline_cursor + output_dur,
                    source_angle=current_angle,
                    source_in=source_in,
                    source_out=source_out,
                    speed_multiplier=speed,
                    audio_on=False,
                    reason="short banter — muted + sped up",
                ))
                timeline_cursor += output_dur
                edl.banter_segments_muted += 1
                log.debug(f"MUTED short banter at t={win.start_sec:.1f}s")
            continue

        # --- Rule 4: New technique lock ---
        technique_lock = False
        for seg in win.transcript_segments:
            if (seg.technique_tag and
                    seg.technique_tag not in seen_techniques):
                seen_techniques.add(seg.technique_tag)
                technique_lock = True
                log.debug(
                    f"New technique '{seg.technique_tag}' at t={win.start_sec:.1f}s "
                    f"→ locking speed to 1.0x"
                )

        # --- Rule 5: Angle switch ---
        if win.preferred_angle != current_angle:
            flush_clip_buffer()
            # Insert dissolve transition
            dissolve_dur = cfg.edl.angle_switch_dissolve_sec
            edl.append(EDLEntry(
                entry_type=EDLEntryType.DISSOLVE,
                timeline_in=timeline_cursor,
                timeline_out=timeline_cursor + dissolve_dur,
                reason=f"angle switch: {current_angle.value} → {win.preferred_angle.value}",
            ))
            timeline_cursor += dissolve_dur
            current_angle = win.preferred_angle
            edl.angle_switches += 1

        # --- Rule 6 & 7: Accumulate into clip buffer with speed tier ---
        if technique_lock:
            # Override: if technique is new, don't let motion tier speed it up.
            # Flush current buffer first so the lock applies cleanly.
            if clip_buffer and _dominant_tier(clip_buffer) != SpeedTier.ACTIVE:
                flush_clip_buffer()
            # Temporarily override the speed tier for this window
            original_tier = win.speed_tier
            win.speed_tier = SpeedTier.ACTIVE
            clip_buffer.append(win)
            win.speed_tier = original_tier  # restore (don't mutate permanently)
        else:
            # If the tier changed, flush before starting the new tier
            if (clip_buffer and
                    _dominant_tier(clip_buffer) != win.speed_tier):
                flush_clip_buffer()
            clip_buffer.append(win)

    # Flush any remaining buffered clip
    flush_clip_buffer()

    edl.total_output_duration_sec = timeline_cursor
    log.info(edl.summary())
    return edl


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def aggregate_windows(
    motion_results_a,
    obstruction_results_a,
    obstruction_results_b,
    transcripts: list[TranscriptSegment],
    window_duration_sec: float = 0.5,
    fps: float = 25.0,
) -> list[AnalysisWindow]:
    """
    Merge per-frame results from Stages 1A and 1B into time windows
    that the EDL engine can consume.

    window_duration_sec: size of each analysis window in seconds.
    """
    if not motion_results_a:
        return []

    total_duration = motion_results_a[-1].timestamp_sec
    windows: list[AnalysisWindow] = []

    # Build timestamp-indexed lookup for obstruction results
    obs_a = _index_by_time(obstruction_results_a, window_duration_sec)
    obs_b = _index_by_time(obstruction_results_b, window_duration_sec)

    t = 0.0
    while t < total_duration:
        t_end = min(t + window_duration_sec, total_duration)

        # Aggregate motion results for this window
        motion_in_window = [
            r for r in motion_results_a
            if t <= r.timestamp_sec < t_end
        ]

        if not motion_in_window:
            t = t_end
            continue

        avg_motion = sum(r.motion_score for r in motion_in_window) / len(motion_in_window)
        is_dead = any(r.is_dead_zone for r in motion_in_window)
        dominant_speed = _dominant_tier(motion_in_window)

        # Aggregate visibility for this window
        win_key = round(t / window_duration_sec)
        vis_a = obs_a.get(win_key, 1.0)
        vis_b = obs_b.get(win_key, 1.0)

        from config import VisionConfig
        obstruction_threshold = 0.55  # use default; ideally pass config through

        preferred = AngleID.A
        if vis_a < obstruction_threshold and vis_b >= obstruction_threshold:
            preferred = AngleID.B

        # Collect transcript segments that overlap this window
        segs_in_window = [
            seg for seg in transcripts
            if seg.start_sec < t_end and seg.end_sec > t
        ]

        # Determine content label for the window (majority vote)
        label = _majority_label(segs_in_window)

        win = AnalysisWindow(
            start_sec=t,
            end_sec=t_end,
            angle_a_visibility=vis_a,
            angle_b_visibility=vis_b,
            preferred_angle=preferred,
            motion_score=avg_motion,
            speed_tier=dominant_speed,
            is_dead_zone=is_dead,
            content_label=label,
            transcript_segments=segs_in_window,
        )
        windows.append(win)
        t = t_end

    return windows


def _dominant_tier(windows_or_results) -> SpeedTier:
    """Return the most common speed tier in a list of windows or motion results."""
    from collections import Counter
    counts = Counter(
        (w.speed_tier if hasattr(w, "speed_tier") else SpeedTier.ACTIVE)
        for w in windows_or_results
    )
    if not counts:
        return SpeedTier.ACTIVE
    return counts.most_common(1)[0][0]


def _majority_label(segments: list[TranscriptSegment]) -> Optional[ContentLabel]:
    """Return the most common content label among a list of segments."""
    if not segments:
        return None
    from collections import Counter
    labels = [s.content_label for s in segments if s.content_label]
    if not labels:
        return None
    return Counter(labels).most_common(1)[0][0]


def _build_transcript_index(
    transcripts: list[TranscriptSegment],
) -> dict[int, TranscriptSegment]:
    """Index transcripts by segment_id for O(1) lookup."""
    return {seg.segment_id: seg for seg in transcripts}


def _collect_subtitles(
    transcript_index: dict[int, TranscriptSegment],
    source_in: float,
    source_out: float,
    timeline_offset: float,
    speed: float,
) -> list[TranscriptSegment]:
    """
    Find transcript segments that overlap [source_in, source_out] and
    adjust their timing to the output timeline (accounting for speed).

    Returns new TranscriptSegment objects with adjusted timestamps — does
    NOT mutate the originals.
    """
    import copy
    result = []
    for seg in transcript_index.values():
        if seg.end_sec <= source_in or seg.start_sec >= source_out:
            continue
        if not seg.english_text:
            continue

        # Clamp to the clip window, then re-map to output timeline
        clamped_start = max(seg.start_sec, source_in)
        clamped_end = min(seg.end_sec, source_out)

        adjusted_start = timeline_offset + (clamped_start - source_in) / speed
        adjusted_end = timeline_offset + (clamped_end - source_in) / speed

        adjusted = copy.copy(seg)
        adjusted.start_sec = adjusted_start
        adjusted.end_sec = adjusted_end
        result.append(adjusted)

    return result


def _emit_title_card(
    edl: EditDecisionList,
    timeline_in: float,
    duration_sec: float,
    text: str = "Later in the class...",
    subtext: str = "",
) -> None:
    edl.append(EDLEntry(
        entry_type=EDLEntryType.TITLE_CARD,
        timeline_in=timeline_in,
        timeline_out=timeline_in + duration_sec,
        title_text=text,
        title_subtext=subtext,
        reason="banter section removed",
    ))


def _index_by_time(results, window_sec: float) -> dict[int, float]:
    """
    Build a window-key → average visibility map from obstruction results.
    Window key = int(timestamp / window_sec).
    """
    bucket: dict[int, list[float]] = defaultdict(list)
    for r in results:
        key = int(r.timestamp_sec / window_sec)
        bucket[key].append(r.canvas_visibility)
    return {k: sum(v) / len(v) for k, v in bucket.items()}
