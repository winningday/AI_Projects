"""
pipeline/stage3_compose.py — Stage 3: FFmpeg composition & rendering.

Takes the EDL and source video files and produces the final output video.

Layout (1920×1080):
  ┌────────────────────────┬──────────────┐
  │                        │  Reference   │
  │   Main painting view   │  Photo       │
  │   (Angle A or B)       │  540×540 px  │
  │   1440×1080 px         ├──────────────┤
  │                        │  Palette Cam │
  │                        │  (Angle C)   │
  │                        │  540×540 px  │
  ├────────────────────────┴──────────────┤
  │  [Subtitle bar — spans full width]    │
  └───────────────────────────────────────┘

Subtitles are burned into the main window area (not over PiP panels).

Speed application uses FFmpeg's minterpolate filter for frame blending
when speed > blend_above_speed, producing smoother slow-motion-style
fast-forward rather than choppy frame-skip.
"""

from __future__ import annotations

import logging
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Optional

from config import WatercolorEditorConfig
from models.edl import EditDecisionList, EDLEntry, EDLEntryType
from models.segment import AngleID

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def render(
    config: WatercolorEditorConfig,
    edl: EditDecisionList,
    angle_paths: dict[str, Optional[str]],   # {"a": path, "b": path, "c": path}
    reference_photo_path: Optional[str],
    subtitle_path: Optional[str],
    output_path: str,
) -> str:
    """
    Render the final video according to the EDL.

    Returns the path to the finished video file.

    Strategy:
      1. Render each EDL clip as a separate intermediate file (handles
         per-clip speed, angle selection, and audio muting).
      2. Concatenate all intermediates into a single timeline.
      3. Apply the PiP composition (reference photo + palette cam overlay).
      4. Burn subtitles.
      5. Final export.
    """
    cfg = config
    render_cfg = config.render
    temp_dir = Path(render_cfg.temp_dir)
    temp_dir.mkdir(parents=True, exist_ok=True)

    output_dir = Path(render_cfg.final_output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    log.info(f"Rendering {len(edl.entries)} EDL entries → {output_path}")

    # Step 1: Render each clip to an intermediate file
    intermediate_files: list[str] = []
    for i, entry in enumerate(edl.entries):
        log.info(
            f"  [{i+1}/{len(edl.entries)}] "
            f"type={entry.entry_type.value} "
            f"t={entry.timeline_in:.1f}–{entry.timeline_out:.1f}s"
        )
        intermediate = _render_entry(
            entry=entry,
            angle_paths=angle_paths,
            temp_dir=temp_dir,
            entry_idx=i,
            cfg=cfg,
        )
        if intermediate:
            intermediate_files.append(intermediate)

    if not intermediate_files:
        raise RuntimeError("No intermediate files produced — EDL may be empty.")

    # Step 2: Concatenate intermediates
    concat_path = str(temp_dir / "concat_main.mp4")
    _concatenate(intermediate_files, concat_path, cfg)

    # Step 3: Compose PiP layout (add reference photo + palette cam)
    composed_path = str(temp_dir / "composed.mp4")
    _compose_pip(
        main_video=concat_path,
        angle_c_path=angle_paths.get("c"),
        reference_photo_path=reference_photo_path,
        output_path=composed_path,
        cfg=cfg,
    )

    # Step 4: Burn subtitles
    if subtitle_path and Path(subtitle_path).exists():
        final_path = output_path
        _burn_subtitles(composed_path, subtitle_path, final_path, cfg)
    else:
        # No subtitles — just copy composed to output
        import shutil
        shutil.copy2(composed_path, output_path)

    # Step 5: Clean up intermediates
    _cleanup_temp_files(intermediate_files + [concat_path, composed_path], temp_dir)

    log.info(f"Render complete: {output_path}")
    return output_path


# ---------------------------------------------------------------------------
# Step 1: Render individual EDL entries
# ---------------------------------------------------------------------------

def _render_entry(
    entry: EDLEntry,
    angle_paths: dict[str, Optional[str]],
    temp_dir: Path,
    entry_idx: int,
    cfg: WatercolorEditorConfig,
) -> Optional[str]:
    """Render a single EDL entry to an intermediate MP4. Returns the path."""
    out_path = str(temp_dir / f"clip_{entry_idx:04d}.mp4")
    render_cfg = cfg.render

    if entry.entry_type == EDLEntryType.TITLE_CARD:
        return _render_title_card(entry, out_path, render_cfg)

    if entry.entry_type == EDLEntryType.DISSOLVE:
        # Dissolves are handled in concatenation; skip here
        return None

    if entry.entry_type != EDLEntryType.CLIP:
        return None

    source_path = angle_paths.get(entry.source_angle.value if entry.source_angle else "a")
    if not source_path:
        log.warning(f"No path for angle {entry.source_angle} — skipping entry {entry_idx}")
        return None

    return _render_clip(entry, source_path, out_path, render_cfg, cfg.motion)


def _render_clip(
    entry: EDLEntry,
    source_path: str,
    out_path: str,
    render_cfg,
    motion_cfg,
) -> str:
    """Render a single CLIP entry with speed and audio settings."""
    speed = entry.speed_multiplier
    source_dur = (entry.source_out or 0) - (entry.source_in or 0)

    # Base input args with source trimming
    cmd = [
        "ffmpeg", "-y",
        "-ss", str(entry.source_in or 0),
        "-t", str(source_dur),
        "-i", source_path,
    ]

    # Build video filter chain
    vf_parts = []

    if speed > motion_cfg.blend_above_speed:
        # Frame blending for smooth fast-forward
        vf_parts.append(f"minterpolate=fps={render_cfg.output_fps}:mi_mode=blend")
        vf_parts.append(f"setpts={1.0/speed:.6f}*PTS")
    else:
        vf_parts.append(f"setpts={1.0/speed:.6f}*PTS")

    vf_parts.append(f"fps={render_cfg.output_fps}")

    vf = ",".join(vf_parts)

    # Audio filter
    if entry.audio_on:
        af = f"atempo={min(speed, 2.0):.3f}"
        # atempo max is 2.0 per filter; chain for higher speeds
        if speed > 2.0:
            af = f"atempo=2.0,atempo={min(speed/2.0, 2.0):.3f}"
        audio_args = ["-af", af]
    else:
        audio_args = ["-an"]

    cmd += [
        "-vf", vf,
        *audio_args,
        "-c:v", render_cfg.output_codec,
        "-crf", str(render_cfg.output_crf),
        "-preset", render_cfg.output_preset,
        "-pix_fmt", render_cfg.pixel_format,
        "-c:a", render_cfg.audio_codec,
        "-b:a", render_cfg.audio_bitrate,
        out_path,
    ]

    _run_ffmpeg(cmd, label=f"clip {out_path}")
    return out_path


def _render_title_card(entry: EDLEntry, out_path: str, render_cfg) -> str:
    """Generate a simple title card (black background + white text)."""
    duration = entry.duration_sec
    text = (entry.title_text or "").replace("'", r"\'").replace(":", r"\:")
    subtext = (entry.title_subtext or "").replace("'", r"\'").replace(":", r"\:")

    drawtext = (
        f"drawtext=text='{text}'"
        f":fontsize=54:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2-30"
        f":fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    )
    if subtext:
        drawtext += (
            f",drawtext=text='{subtext}'"
            f":fontsize=30:fontcolor=gray:x=(w-text_w)/2:y=(h+text_h)/2+10"
            f":fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
        )

    cmd = [
        "ffmpeg", "-y",
        "-f", "lavfi",
        "-i", f"color=c=black:s=1920x1080:d={duration}:r={render_cfg.output_fps}",
        "-f", "lavfi",
        "-i", f"anullsrc=channel_layout=stereo:sample_rate=44100",
        "-vf", drawtext,
        "-t", str(duration),
        "-c:v", render_cfg.output_codec,
        "-crf", str(render_cfg.output_crf),
        "-pix_fmt", render_cfg.pixel_format,
        "-c:a", render_cfg.audio_codec,
        "-b:a", render_cfg.audio_bitrate,
        out_path,
    ]
    _run_ffmpeg(cmd, label="title card")
    return out_path


# ---------------------------------------------------------------------------
# Step 2: Concatenation
# ---------------------------------------------------------------------------

def _concatenate(files: list[str], output_path: str, cfg: WatercolorEditorConfig) -> None:
    """Concatenate intermediate clips using FFmpeg concat demuxer."""
    list_path = str(Path(cfg.render.temp_dir) / "concat_list.txt")
    with open(list_path, "w") as f:
        for fp in files:
            f.write(f"file '{os.path.abspath(fp)}'\n")

    cmd = [
        "ffmpeg", "-y",
        "-f", "concat",
        "-safe", "0",
        "-i", list_path,
        "-c", "copy",
        output_path,
    ]
    _run_ffmpeg(cmd, label="concatenation")


# ---------------------------------------------------------------------------
# Step 3: PiP Composition
# ---------------------------------------------------------------------------

def _compose_pip(
    main_video: str,
    angle_c_path: Optional[str],
    reference_photo_path: Optional[str],
    output_path: str,
    cfg: WatercolorEditorConfig,
) -> None:
    """
    Overlay the reference photo (top-right) and palette cam (bottom-right)
    onto the main painting view video.

    Final output: 1920×1080
    Main area: 1440×1080 (left)
    Right column: 480×1080, split into:
      - Top 540px: reference photo (static)
      - Bottom 540px: palette cam (live video)
    """
    layout = cfg.layout
    W = layout.output_width          # 1920
    H = layout.output_height         # 1080
    main_w = int(W * layout.main_width_pct)          # 1440
    side_w = W - main_w                               # 480
    ref_h = int(H * layout.ref_height_pct)            # 540
    palette_h = H - ref_h                             # 540

    inputs = ["-i", main_video]
    filter_parts = []
    input_count = 1

    # Scale main video to fill main area
    filter_parts.append(f"[0:v]scale={main_w}:{H}[main]")
    current = "[main]"

    # Overlay reference photo (top-right)
    if reference_photo_path:
        inputs += ["-loop", "1", "-i", reference_photo_path]
        filter_parts.append(
            f"[{input_count}:v]scale={side_w}:{ref_h}[ref]"
        )
        filter_parts.append(
            f"{current}[ref]overlay={main_w}:0[with_ref]"
        )
        current = "[with_ref]"
        input_count += 1
    else:
        # Black panel for reference area
        filter_parts.append(
            f"color=c=black:s={side_w}x{ref_h}[ref]"
        )
        filter_parts.append(f"{current}[ref]overlay={main_w}:0[with_ref]")
        current = "[with_ref]"

    # Overlay palette camera (bottom-right)
    if angle_c_path:
        inputs += ["-i", angle_c_path]
        filter_parts.append(
            f"[{input_count}:v]scale={side_w}:{palette_h}[palette]"
        )
        filter_parts.append(
            f"{current}[palette]overlay={main_w}:{ref_h}[composed]"
        )
        current = "[composed]"
        input_count += 1
    else:
        filter_parts.append(
            f"color=c=black:s={side_w}x{palette_h}[palette]"
        )
        filter_parts.append(
            f"{current}[palette]overlay={main_w}:{ref_h}[composed]"
        )
        current = "[composed]"

    # Final scale to ensure exact output dimensions
    filter_parts.append(f"{current}scale={W}:{H}[out]")

    filter_complex = ";".join(filter_parts)

    cmd = [
        "ffmpeg", "-y",
        *inputs,
        "-filter_complex", filter_complex,
        "-map", "[out]",
        "-map", "0:a",       # audio from main video
        "-c:v", cfg.render.output_codec,
        "-crf", str(cfg.render.output_crf),
        "-preset", cfg.render.output_preset,
        "-pix_fmt", cfg.render.pixel_format,
        "-c:a", "copy",
        output_path,
    ]
    _run_ffmpeg(cmd, label="PiP composition")


# ---------------------------------------------------------------------------
# Step 4: Subtitle burn-in
# ---------------------------------------------------------------------------

def _burn_subtitles(
    video_path: str,
    subtitle_path: str,
    output_path: str,
    cfg: WatercolorEditorConfig,
) -> None:
    """Burn subtitles into the lower portion of the main window."""
    layout = cfg.layout
    font_size = layout.subtitle_font_size
    font_color = layout.subtitle_font_color

    # Subtitle position: centred horizontally within the main window area,
    # near the bottom of the frame
    sub_filter = (
        f"subtitles={subtitle_path}"
        f":force_style='FontSize={font_size},"
        f"PrimaryColour=&H00FFFFFF,"
        f"OutlineColour=&H00000000,"
        f"BackColour=&H80000000,"
        f"Outline=2,Shadow=1,"
        f"MarginV=40,"
        f"Alignment=2'"   # bottom-centre
    )

    cmd = [
        "ffmpeg", "-y",
        "-i", video_path,
        "-vf", sub_filter,
        "-c:v", cfg.render.output_codec,
        "-crf", str(cfg.render.output_crf),
        "-preset", cfg.render.output_preset,
        "-pix_fmt", cfg.render.pixel_format,
        "-c:a", "copy",
        output_path,
    ]
    _run_ffmpeg(cmd, label="subtitle burn-in")


# ---------------------------------------------------------------------------
# FFmpeg runner
# ---------------------------------------------------------------------------

def _run_ffmpeg(cmd: list[str], label: str = "") -> None:
    """Run an FFmpeg command, logging stderr on failure."""
    log.debug(f"FFmpeg [{label}]: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        log.error(f"FFmpeg failed [{label}]:\n{result.stderr[-3000:]}")
        raise RuntimeError(f"FFmpeg error on {label}. See log for details.")


def _cleanup_temp_files(files: list[str], temp_dir: Path) -> None:
    """Remove intermediate files after successful render."""
    for fp in files:
        try:
            Path(fp).unlink(missing_ok=True)
        except Exception as e:
            log.warning(f"Could not remove temp file {fp}: {e}")
    # Remove concat list if it exists
    (temp_dir / "concat_list.txt").unlink(missing_ok=True)
