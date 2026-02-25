"""
pipeline/stage0_sync.py — Stage 0: Multi-angle audio sync & timeline alignment.

Problem: Three cameras started at different times and may drift.
Solution: Cross-correlate audio waveforms to find the offset for each
          secondary angle relative to the primary, then optionally
          check for drift at regular intervals.

Usage:
    from pipeline.stage0_sync import sync_angles
    offsets = sync_angles(config)
    # offsets["b"] = 2.34  means angle B starts 2.34s AFTER angle A
"""

from __future__ import annotations

import logging
import subprocess
import tempfile
from pathlib import Path
from typing import Optional

import numpy as np

from config import WatercolorEditorConfig

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def sync_angles(config: WatercolorEditorConfig) -> dict[str, float]:
    """
    Compute the time offset (seconds) for each angle relative to Angle A.

    Returns a dict like:
        {"a": 0.0, "b": 2.34, "c": -0.81}

    A positive offset means that angle starts LATER than A in real-world time,
    so we trim that many seconds from its start.
    A negative offset means A starts later; trim from A (or pad others).
    """
    cfg = config.sync
    cam = config.cameras

    paths = {
        "a": cam.angle_a_path,
        "b": cam.angle_b_path,
        "c": cam.angle_c_path,
    }

    # Extract audio from the alignment window for each available angle
    audio_arrays: dict[str, np.ndarray] = {}
    sr = cfg.correlation_sr

    for angle_id, path in paths.items():
        if path is None:
            continue
        log.info(f"Extracting alignment audio from angle {angle_id.upper()}: {path}")
        audio_arrays[angle_id] = _extract_audio_array(
            path, sr=sr, duration_sec=cfg.alignment_window_sec
        )

    if "a" not in audio_arrays:
        raise ValueError("Angle A path is required — it is the sync reference.")

    offsets: dict[str, float] = {"a": 0.0}
    reference = audio_arrays["a"]

    for angle_id, audio in audio_arrays.items():
        if angle_id == "a":
            continue
        offset_sec = _cross_correlate_offset(reference, audio, sr)
        log.info(
            f"Angle {angle_id.upper()} offset vs A: {offset_sec:+.3f}s"
        )
        offsets[angle_id] = offset_sec

    _warn_on_large_offsets(offsets, cfg.max_drift_warning_sec)
    return offsets


def check_drift(
    config: WatercolorEditorConfig,
    offsets: dict[str, float],
    checkpoint_sec: float,
) -> dict[str, float]:
    """
    Re-check alignment at a mid-video checkpoint to detect drift.

    Returns updated offsets (cumulative from the start of recording).
    Call this every sync.drift_check_interval_sec of source footage.
    """
    cfg = config.sync
    cam = config.cameras
    sr = cfg.correlation_sr

    paths = {
        "a": cam.angle_a_path,
        "b": cam.angle_b_path,
        "c": cam.angle_c_path,
    }

    # We re-extract audio starting at the checkpoint for each angle,
    # accounting for the already-known offset so we look at the same
    # real-world moment.
    reference_arrays: dict[str, np.ndarray] = {}
    for angle_id, path in paths.items():
        if path is None or angle_id not in offsets:
            continue
        # The angle's local timestamp at checkpoint_sec of A's timeline
        angle_local_start = checkpoint_sec + offsets[angle_id]
        reference_arrays[angle_id] = _extract_audio_array(
            path,
            sr=sr,
            start_sec=max(0.0, angle_local_start),
            duration_sec=cfg.alignment_window_sec,
        )

    if "a" not in reference_arrays:
        log.warning("Could not extract drift checkpoint audio — skipping.")
        return offsets

    updated: dict[str, float] = {"a": 0.0}
    reference = reference_arrays["a"]

    for angle_id, audio in reference_arrays.items():
        if angle_id == "a":
            continue
        local_offset = _cross_correlate_offset(reference, audio, sr)
        # Cumulative: original offset + drift discovered at checkpoint
        total_offset = offsets.get(angle_id, 0.0) + local_offset
        drift = abs(local_offset)
        if drift > 0.1:
            log.warning(
                f"Drift detected on angle {angle_id.upper()} at "
                f"t={checkpoint_sec:.0f}s: {local_offset:+.3f}s additional drift "
                f"(total offset now {total_offset:+.3f}s)"
            )
        updated[angle_id] = total_offset

    return updated


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _extract_audio_array(
    video_path: str,
    sr: int = 16_000,
    start_sec: float = 0.0,
    duration_sec: Optional[float] = None,
) -> np.ndarray:
    """
    Use FFmpeg to extract mono audio from a video file as a numpy float32 array.

    We use FFmpeg directly rather than librosa.load() to avoid loading the
    entire video into memory for large files.
    """
    cmd = [
        "ffmpeg", "-y",
        "-ss", str(start_sec),
        "-i", video_path,
    ]
    if duration_sec is not None:
        cmd += ["-t", str(duration_sec)]

    cmd += [
        "-vn",                          # no video
        "-acodec", "pcm_f32le",         # 32-bit float PCM
        "-ar", str(sr),                 # resample to target sr
        "-ac", "1",                     # mono
        "-f", "f32le",                  # raw format
        "pipe:1",                       # output to stdout
    ]

    result = subprocess.run(cmd, capture_output=True, check=True)
    audio = np.frombuffer(result.stdout, dtype=np.float32).copy()

    if len(audio) == 0:
        raise RuntimeError(
            f"FFmpeg returned empty audio for {video_path}. "
            "Check that the file contains an audio track."
        )

    # Normalise to [-1, 1] to make correlation comparable across cameras
    # with different recording levels
    peak = np.abs(audio).max()
    if peak > 0:
        audio /= peak

    return audio


def _cross_correlate_offset(reference: np.ndarray, query: np.ndarray, sr: int) -> float:
    """
    Find the time offset of query relative to reference using cross-correlation.

    Returns offset_sec where:
        positive → query starts AFTER reference
        negative → query starts BEFORE reference

    We use FFT-based correlation (O(n log n)) for speed on long windows.
    """
    # Pad both to the same length (next power of 2 for FFT efficiency)
    n = len(reference) + len(query) - 1
    fft_len = int(2 ** np.ceil(np.log2(n)))

    ref_fft = np.fft.rfft(reference, n=fft_len)
    qry_fft = np.fft.rfft(query, n=fft_len)

    # Cross-correlation in frequency domain
    correlation = np.fft.irfft(ref_fft * np.conj(qry_fft))

    # The lag at peak correlation
    peak_index = int(np.argmax(np.abs(correlation)))

    # Convert from circular correlation index to signed lag
    if peak_index > fft_len // 2:
        peak_index -= fft_len

    offset_sec = peak_index / sr
    return offset_sec


def _warn_on_large_offsets(offsets: dict[str, float], threshold_sec: float) -> None:
    for angle_id, offset in offsets.items():
        if abs(offset) > threshold_sec:
            log.warning(
                f"Angle {angle_id.upper()} has a large sync offset of "
                f"{offset:+.2f}s (threshold: ±{threshold_sec}s). "
                "Verify the sync clap was captured on all cameras."
            )


# ---------------------------------------------------------------------------
# CLI helper for manual inspection
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse
    import json

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    parser = argparse.ArgumentParser(description="Compute sync offsets for 3 camera angles")
    parser.add_argument("--angle-a", required=True, help="Path to angle A video")
    parser.add_argument("--angle-b", help="Path to angle B video")
    parser.add_argument("--angle-c", help="Path to angle C video")
    parser.add_argument("--window", type=float, default=30.0,
                        help="Alignment window in seconds (default: 30)")
    args = parser.parse_args()

    from config import WatercolorEditorConfig, CameraConfig, SyncConfig
    cfg = WatercolorEditorConfig(
        cameras=CameraConfig(
            angle_a_path=args.angle_a,
            angle_b_path=args.angle_b,
            angle_c_path=args.angle_c,
        ),
        sync=SyncConfig(alignment_window_sec=args.window),
    )

    offsets = sync_angles(cfg)
    print(json.dumps(offsets, indent=2))
