"""
utils/ffmpeg_utils.py — FFmpeg utility helpers.
"""

from __future__ import annotations

import subprocess
import json
import logging
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)


def probe_video(path: str) -> dict:
    """
    Run ffprobe on a video file and return stream information as a dict.
    Raises RuntimeError if the file cannot be probed.
    """
    cmd = [
        "ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_streams", "-show_format",
        path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"ffprobe failed on {path}:\n{result.stderr}"
        )
    return json.loads(result.stdout)


def get_video_duration(path: str) -> float:
    """Return video duration in seconds."""
    info = probe_video(path)
    duration = float(info.get("format", {}).get("duration", 0))
    if duration == 0:
        # Try from stream
        for stream in info.get("streams", []):
            if stream.get("codec_type") == "video":
                duration = float(stream.get("duration", 0))
                break
    return duration


def get_video_fps(path: str) -> float:
    """Return video frame rate as a float."""
    info = probe_video(path)
    for stream in info.get("streams", []):
        if stream.get("codec_type") == "video":
            r_frame_rate = stream.get("r_frame_rate", "25/1")
            num, den = r_frame_rate.split("/")
            return float(num) / float(den)
    return 25.0


def get_video_dimensions(path: str) -> tuple[int, int]:
    """Return (width, height) of the video in pixels."""
    info = probe_video(path)
    for stream in info.get("streams", []):
        if stream.get("codec_type") == "video":
            return int(stream["width"]), int(stream["height"])
    raise RuntimeError(f"No video stream found in {path}")


def has_audio_track(path: str) -> bool:
    """Return True if the video file has at least one audio stream."""
    info = probe_video(path)
    return any(
        s.get("codec_type") == "audio"
        for s in info.get("streams", [])
    )


def check_ffmpeg_available() -> bool:
    """Return True if FFmpeg is installed and accessible."""
    try:
        subprocess.run(
            ["ffmpeg", "-version"],
            capture_output=True, check=True
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def check_ffprobe_available() -> bool:
    """Return True if ffprobe is installed and accessible."""
    try:
        subprocess.run(
            ["ffprobe", "-version"],
            capture_output=True, check=True
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False
