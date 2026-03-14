"""
pipeline/stage1b_motion.py — Stage 1B: Motion scoring, speed tiers, dead zones.

For each frame (within the canvas ROI), we compute a motion score using
frame-to-frame pixel difference. This score is smoothed over a rolling
window and mapped to a speed tier.

Dead zones (motion below threshold for > dead_zone_min_sec) are flagged
for removal by the EDL engine.

Key editorial principle enforced here:
  A speed tier is ONLY applied if it lasts at least min_speed_segment_sec.
  Micro-speedups feel jarring and are collapsed back to the surrounding tier.
"""

from __future__ import annotations

import logging
from collections import deque
from typing import Optional

import cv2
import numpy as np

from config import WatercolorEditorConfig
from models.segment import AngleID, MotionResult, SpeedTier
from pipeline.stage1a_vision import get_canvas_roi_pixels

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def analyse_motion(
    config: WatercolorEditorConfig,
    angle: AngleID,
    video_path: str,
    canvas_roi_frac: tuple[float, float, float, float],
    start_offset_sec: float = 0.0,
) -> list[MotionResult]:
    """
    Compute per-frame motion results for a video file.

    canvas_roi_frac: (x, y, w, h) as fractions of the frame.
    start_offset_sec: sync offset so timestamps are in the shared timeline.
    """
    cfg = config.motion

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    log.info(
        f"Angle {angle.value.upper()}: motion analysis "
        f"({total_frames} frames @ {fps:.1f}fps)"
    )

    smoothing_window = int(cfg.smoothing_window_sec * fps)
    score_buffer: deque[float] = deque(maxlen=max(1, smoothing_window))

    prev_roi: Optional[np.ndarray] = None
    raw_results: list[tuple[float, float]] = []  # (timestamp_sec, raw_score)

    frame_idx = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break

        timestamp_sec = (frame_idx / fps) - start_offset_sec
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        x1, y1, x2, y2 = get_canvas_roi_pixels(frame, canvas_roi_frac)
        roi = gray[y1:y2, x1:x2]

        if prev_roi is not None and roi.shape == prev_roi.shape:
            diff = cv2.absdiff(roi, prev_roi)
            score = float(np.mean(diff))
        else:
            score = 0.0

        score_buffer.append(score)
        smoothed_score = float(np.mean(score_buffer))
        raw_results.append((timestamp_sec, smoothed_score))

        prev_roi = roi
        frame_idx += 1

    cap.release()

    # Map scores → speed tiers
    motion_results = _assign_speed_tiers(raw_results, cfg)

    # Mark dead zones
    motion_results = _mark_dead_zones(motion_results, cfg, fps)

    # Collapse micro-segments (enforce min_speed_segment_sec)
    motion_results = _collapse_micro_segments(motion_results, cfg, fps)

    log.info(
        f"Angle {angle.value.upper()}: motion analysis complete. "
        f"Dead zones: {sum(r.is_dead_zone for r in motion_results)} frames. "
        f"Speed tiers: {_tier_summary(motion_results)}"
    )
    return motion_results


# ---------------------------------------------------------------------------
# Internal: scoring → tier assignment
# ---------------------------------------------------------------------------

def _assign_speed_tiers(
    raw_results: list[tuple[float, float]],
    cfg,
) -> list[MotionResult]:
    results: list[MotionResult] = []
    for timestamp_sec, score in raw_results:
        tier = _score_to_tier(score, cfg)
        results.append(MotionResult(
            timestamp_sec=timestamp_sec,
            motion_score=score,
            speed_tier=tier,
        ))
    return results


def _score_to_tier(score: float, cfg) -> SpeedTier:
    """Map a smoothed motion score to a speed tier."""
    if score >= cfg.active_threshold:
        return SpeedTier.ACTIVE
    elif score >= cfg.slow_threshold:
        return SpeedTier.SLOW
    elif score >= cfg.idle_threshold:
        return SpeedTier.IDLE
    else:
        return SpeedTier.CUT   # Potential dead zone — refined below


def _mark_dead_zones(
    results: list[MotionResult],
    cfg,
    fps: float,
) -> list[MotionResult]:
    """
    A dead zone is a consecutive run of CUT-tier frames lasting at least
    dead_zone_min_sec. Short CUT-tier runs (< threshold) are promoted to IDLE.
    """
    min_dead_frames = int(cfg.dead_zone_min_sec * fps)
    i = 0
    while i < len(results):
        if results[i].speed_tier == SpeedTier.CUT:
            j = i
            while j < len(results) and results[j].speed_tier == SpeedTier.CUT:
                j += 1
            run_length = j - i
            if run_length >= min_dead_frames:
                # True dead zone — mark it
                for k in range(i, j):
                    results[k].is_dead_zone = True
            else:
                # Short pause — promote to IDLE (slow it down but don't cut)
                for k in range(i, j):
                    results[k].speed_tier = SpeedTier.IDLE
            i = j
        else:
            i += 1
    return results


def _collapse_micro_segments(
    results: list[MotionResult],
    cfg,
    fps: float,
) -> list[MotionResult]:
    """
    Enforce minimum segment duration (min_speed_segment_sec).

    A speed tier change that reverts after fewer than min frames is
    collapsed into the surrounding tier. This prevents the flickery
    feel of many rapid tier changes.
    """
    min_frames = int(cfg.min_speed_segment_sec * fps)
    if min_frames <= 1 or not results:
        return results

    changed = True
    while changed:
        changed = False
        i = 0
        while i < len(results):
            if results[i].is_dead_zone:
                i += 1
                continue

            current_tier = results[i].speed_tier
            j = i
            while (j < len(results)
                   and results[j].speed_tier == current_tier
                   and not results[j].is_dead_zone):
                j += 1

            run_length = j - i
            if run_length < min_frames:
                # Collapse: inherit tier from the frame before this run
                replacement_tier = (
                    results[i - 1].speed_tier if i > 0 else SpeedTier.ACTIVE
                )
                for k in range(i, j):
                    results[k].speed_tier = replacement_tier
                changed = True

            i = j

    return results


# ---------------------------------------------------------------------------
# Speed multiplier lookup
# ---------------------------------------------------------------------------

def tier_to_multiplier(tier: SpeedTier, cfg) -> float:
    """Return the playback speed multiplier for a given tier."""
    mapping = {
        SpeedTier.ACTIVE: cfg.speed_active,
        SpeedTier.SLOW:   cfg.speed_slow,
        SpeedTier.IDLE:   cfg.speed_idle,
        SpeedTier.CUT:    cfg.speed_max,   # Dead zones use max (or cut)
    }
    return mapping.get(tier, 1.0)


# ---------------------------------------------------------------------------
# Debug helpers
# ---------------------------------------------------------------------------

def _tier_summary(results: list[MotionResult]) -> str:
    from collections import Counter
    counts = Counter(r.speed_tier for r in results if not r.is_dead_zone)
    return ", ".join(f"{t.value}={c}" for t, c in counts.most_common())


def visualise_motion_scores(
    results: list[MotionResult],
    output_path: str,
    width: int = 1200,
    height: int = 300,
) -> None:
    """
    Render a simple bar chart of motion scores to a PNG for debugging.
    Only produces output if opencv is available with GUI support.
    """
    if not results:
        return

    scores = np.array([r.motion_score for r in results])
    scores_norm = scores / max(scores.max(), 1.0)

    img = np.ones((height, width, 3), dtype=np.uint8) * 30  # dark background

    tier_colors = {
        SpeedTier.ACTIVE: (0, 200, 80),    # green
        SpeedTier.SLOW:   (0, 180, 255),   # yellow-ish
        SpeedTier.IDLE:   (0, 100, 255),   # orange
        SpeedTier.CUT:    (0, 0, 200),     # red
    }

    bar_w = max(1, width // len(results))
    for i, result in enumerate(results):
        x = i * bar_w
        bar_h = int(scores_norm[i] * (height - 20))
        color = tier_colors.get(result.speed_tier, (128, 128, 128))
        if result.is_dead_zone:
            color = (0, 0, 200)
        cv2.rectangle(img, (x, height - bar_h), (x + bar_w, height), color, -1)

    cv2.imwrite(output_path, img)
    log.info(f"Motion score visualisation saved to {output_path}")
