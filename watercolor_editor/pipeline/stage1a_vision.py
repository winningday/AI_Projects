"""
pipeline/stage1a_vision.py — Stage 1A: Canvas visibility & obstruction detection.

For each frame of Angles A and B, we compute what fraction of the defined
canvas ROI is unobstructed by the instructor's hands or body.

When angle A's canvas visibility drops below config.vision.obstruction_threshold
for at least config.vision.obstruction_min_frames consecutive frames,
we flag those frames as preferring angle B.

Design notes:
  - Canvas ROI is set manually once per project (in config) because
    auto-detection is fragile across different studio setups.
  - We use MediaPipe Hands to detect hand landmarks. When hand landmarks
    fall inside the canvas ROI, we estimate occlusion from the convex hull
    of those landmarks relative to the ROI area.
  - Falls back to a simpler background-subtraction method if MediaPipe
    is not available or landmark confidence is low.
"""

from __future__ import annotations

import logging
from typing import Generator

import cv2
import numpy as np

from config import WatercolorEditorConfig
from models.segment import AngleID, ObstructionResult

log = logging.getLogger(__name__)

# Optional MediaPipe import — degrade gracefully if not installed
try:
    import mediapipe as mp
    _MP_AVAILABLE = True
    _mp_hands = mp.solutions.hands
except ImportError:
    _MP_AVAILABLE = False
    log.warning(
        "mediapipe not installed. Falling back to background-subtraction "
        "obstruction detection. Install with: pip install mediapipe"
    )


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def analyse_obstruction(
    config: WatercolorEditorConfig,
    angle: AngleID,
    video_path: str,
    start_offset_sec: float = 0.0,
) -> list[ObstructionResult]:
    """
    Analyse every frame of video_path and return an ObstructionResult per frame.

    start_offset_sec: the sync offset computed by Stage 0 for this angle,
    so that result timestamps are in the shared timeline (relative to angle A).
    """
    cfg = config.vision

    canvas_roi_frac = (
        cfg.canvas_roi_a if angle == AngleID.A else cfg.canvas_roi_b
    )

    results: list[ObstructionResult] = []

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    log.info(
        f"Angle {angle.value.upper()}: analysing obstruction "
        f"({total_frames} frames @ {fps:.1f}fps)"
    )

    if _MP_AVAILABLE:
        detector = _HandObstructionDetector(cfg, canvas_roi_frac)
    else:
        detector = _BGSubtractObstructionDetector(cfg, canvas_roi_frac)

    frame_idx = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break

        # Timeline timestamp (shared reference, angle A's clock)
        timestamp_sec = (frame_idx / fps) - start_offset_sec

        visibility = detector.compute_visibility(frame)
        is_obstructed = visibility < cfg.obstruction_threshold

        results.append(ObstructionResult(
            timestamp_sec=timestamp_sec,
            angle=angle,
            canvas_visibility=visibility,
            is_obstructed=is_obstructed,
        ))
        frame_idx += 1

    cap.release()

    # Post-process: require min_frames consecutive obstruction before flagging
    results = _apply_hysteresis(results, cfg.obstruction_min_frames)

    log.info(
        f"Angle {angle.value.upper()}: obstruction analysis complete. "
        f"{sum(r.is_obstructed for r in results)} / {len(results)} frames obstructed."
    )
    return results


def select_angle_per_frame(
    results_a: list[ObstructionResult],
    results_b: list[ObstructionResult],
) -> list[tuple[float, AngleID]]:
    """
    Combine obstruction results for angles A and B into a per-frame
    angle selection list: [(timestamp_sec, preferred_angle), ...]

    Rule: prefer A unless A is obstructed AND B is not.
    """
    # Build a lookup dict for B results by rounded timestamp
    b_by_ts: dict[int, ObstructionResult] = {}
    for r in results_b:
        key = round(r.timestamp_sec * 1000)  # millisecond precision key
        b_by_ts[key] = r

    selections: list[tuple[float, AngleID]] = []
    for r_a in results_a:
        key = round(r_a.timestamp_sec * 1000)
        r_b = b_by_ts.get(key)

        if r_a.is_obstructed and r_b is not None and not r_b.is_obstructed:
            angle = AngleID.B
        else:
            angle = AngleID.A

        selections.append((r_a.timestamp_sec, angle))

    return selections


def get_canvas_roi_pixels(
    frame: np.ndarray,
    roi_frac: tuple[float, float, float, float],
) -> tuple[int, int, int, int]:
    """
    Convert fractional ROI (x, y, w, h) to pixel coordinates for a given frame.
    Returns (x1, y1, x2, y2) in pixels.
    """
    h, w = frame.shape[:2]
    x1 = int(roi_frac[0] * w)
    y1 = int(roi_frac[1] * h)
    x2 = int((roi_frac[0] + roi_frac[2]) * w)
    y2 = int((roi_frac[1] + roi_frac[3]) * h)
    return x1, y1, x2, y2


# ---------------------------------------------------------------------------
# Obstruction detectors
# ---------------------------------------------------------------------------

class _HandObstructionDetector:
    """
    Uses MediaPipe Hands to detect hand landmarks and estimate how much
    of the canvas ROI they cover.
    """

    def __init__(self, cfg, canvas_roi_frac: tuple):
        self.cfg = cfg
        self.canvas_roi_frac = canvas_roi_frac
        self.hands = _mp_hands.Hands(
            static_image_mode=False,
            max_num_hands=2,
            min_detection_confidence=cfg.hand_detection_confidence,
            min_tracking_confidence=cfg.hand_tracking_confidence,
        )

    def compute_visibility(self, frame: np.ndarray) -> float:
        h, w = frame.shape[:2]
        x1, y1, x2, y2 = get_canvas_roi_pixels(frame, self.canvas_roi_frac)
        roi_area = max(1, (x2 - x1) * (y2 - y1))

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        result = self.hands.process(rgb)

        if not result.multi_hand_landmarks:
            return 1.0  # No hands detected → fully visible

        # Build a mask of pixels covered by hand convex hulls within the ROI
        hand_mask = np.zeros((h, w), dtype=np.uint8)

        for hand_landmarks in result.multi_hand_landmarks:
            points = np.array(
                [[int(lm.x * w), int(lm.y * h)] for lm in hand_landmarks.landmark],
                dtype=np.int32,
            )
            hull = cv2.convexHull(points)
            cv2.fillPoly(hand_mask, [hull], 255)

        # Count covered pixels within canvas ROI
        roi_mask = hand_mask[y1:y2, x1:x2]
        covered_pixels = int(np.count_nonzero(roi_mask))
        visibility = 1.0 - (covered_pixels / roi_area)
        return max(0.0, visibility)

    def __del__(self):
        if hasattr(self, "hands"):
            self.hands.close()


class _BGSubtractObstructionDetector:
    """
    Fallback: background subtraction approach.

    We initialise a background model from the first N frames (assumed to show
    the empty canvas) then treat significant foreground blobs within the
    canvas ROI as potential obstructions.
    """
    WARMUP_FRAMES = 60  # frames to use for background model initialisation

    def __init__(self, cfg, canvas_roi_frac: tuple):
        self.cfg = cfg
        self.canvas_roi_frac = canvas_roi_frac
        self.bg_subtractor = cv2.createBackgroundSubtractorMOG2(
            history=200, varThreshold=50, detectShadows=False
        )
        self._frame_count = 0

    def compute_visibility(self, frame: np.ndarray) -> float:
        h, w = frame.shape[:2]
        x1, y1, x2, y2 = get_canvas_roi_pixels(frame, self.canvas_roi_frac)
        roi_area = max(1, (x2 - x1) * (y2 - y1))

        fg_mask = self.bg_subtractor.apply(frame)
        self._frame_count += 1

        # During warmup we don't flag obstructions
        if self._frame_count < self.WARMUP_FRAMES:
            return 1.0

        roi_fg = fg_mask[y1:y2, x1:x2]
        foreground_pixels = int(np.count_nonzero(roi_fg))
        visibility = 1.0 - (foreground_pixels / roi_area)
        return max(0.0, visibility)


# ---------------------------------------------------------------------------
# Post-processing
# ---------------------------------------------------------------------------

def _apply_hysteresis(
    results: list[ObstructionResult],
    min_frames: int,
) -> list[ObstructionResult]:
    """
    Only mark a frame as obstructed if it is part of a run of at least
    min_frames consecutive obstructed frames. This prevents flickering
    from brief hand passes across the canvas edge.
    """
    if not results:
        return results

    flags = [r.is_obstructed for r in results]
    smoothed = list(flags)  # copy

    i = 0
    while i < len(flags):
        if flags[i]:
            # Find the end of this run
            j = i
            while j < len(flags) and flags[j]:
                j += 1
            run_length = j - i
            if run_length < min_frames:
                # Too short — clear the obstruction flag for this run
                for k in range(i, j):
                    smoothed[k] = False
            i = j
        else:
            i += 1

    for idx, result in enumerate(results):
        result.is_obstructed = smoothed[idx]

    return results
