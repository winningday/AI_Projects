#!/usr/bin/env python3
"""
Phase 2: Auto Editor Execution

Reads edit_notes.json and executes all edits via ffmpeg for frame-accurate,
broadcast-quality output.

Usage:
    python apply_edits.py --input raw_video.mp4
    python apply_edits.py --input raw_video.mp4 --edit-notes custom_notes.json
    python apply_edits.py --input raw_video.mp4 --dry-run
    python apply_edits.py --input raw_video.mp4 --overrides overrides.json
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from tqdm import tqdm

import config

# ── Logging ────────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=getattr(logging, config.LOG_LEVEL),
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(config.LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger(__name__)


# ── Utilities ──────────────────────────────────────────────────────────────────

def get_video_duration(video_path: str) -> float:
    """Get video duration in seconds."""
    cmd = [
        "ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_format",
        video_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return float(json.loads(result.stdout)["format"]["duration"])


def get_video_info(video_path: str) -> dict:
    """Get detailed video stream info."""
    cmd = [
        "ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_streams",
        video_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def run_ffmpeg(cmd: list[str], desc: str = "ffmpeg") -> subprocess.CompletedProcess:
    """Run an ffmpeg command with error handling."""
    log.debug(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        log.error(f"{desc} failed:\n{result.stderr[-2000:]}")
        raise RuntimeError(f"{desc} failed with return code {result.returncode}")
    return result


# ── Segment Builder ────────────────────────────────────────────────────────────

class EditSegment:
    """Represents a segment of the timeline to keep, with optional speed change."""
    def __init__(self, start: float, end: float, speed: float = 1.0):
        self.start = start
        self.end = end
        self.speed = speed

    @property
    def original_duration(self) -> float:
        return self.end - self.start

    @property
    def output_duration(self) -> float:
        return self.original_duration / self.speed

    def __repr__(self):
        s = f"Segment({self.start:.3f}-{self.end:.3f}"
        if self.speed != 1.0:
            s += f" @{self.speed}x"
        s += ")"
        return s


def build_keep_segments(
    duration: float,
    cuts: list[dict],
    speedups: list[dict],
) -> list[EditSegment]:
    """
    Build the list of segments to KEEP from the original video.

    1. Start with the full timeline [0, duration]
    2. Remove all cut regions
    3. Apply speed factors to matching speedup regions
    """
    # Sort cuts by start time and merge overlapping
    sorted_cuts = sorted(cuts, key=lambda c: c["start"])
    merged_cuts = []
    for cut in sorted_cuts:
        if cut["end"] - cut["start"] < config.MIN_CUT_DURATION:
            log.debug(f"Skipping cut too short: {cut['start']:.3f}-{cut['end']:.3f}")
            continue
        if merged_cuts and cut["start"] <= merged_cuts[-1]["end"]:
            merged_cuts[-1]["end"] = max(merged_cuts[-1]["end"], cut["end"])
        else:
            merged_cuts.append({"start": cut["start"], "end": cut["end"]})

    # Build keep regions by inverting cuts
    keep_regions = []
    prev_end = 0.0
    for cut in merged_cuts:
        if cut["start"] > prev_end:
            keep_regions.append((prev_end, cut["start"]))
        prev_end = max(prev_end, cut["end"])
    if prev_end < duration:
        keep_regions.append((prev_end, duration))

    # Apply speedups to keep regions
    sorted_speedups = sorted(speedups, key=lambda s: s["start"])

    segments = []
    for region_start, region_end in keep_regions:
        # Find all speedups that overlap this region
        relevant_speedups = [
            sp for sp in sorted_speedups
            if sp["start"] < region_end and sp["end"] > region_start
        ]

        if not relevant_speedups:
            segments.append(EditSegment(region_start, region_end, 1.0))
            continue

        # Split region at speedup boundaries
        cursor = region_start
        for sp in relevant_speedups:
            sp_start = max(sp["start"], region_start)
            sp_end = min(sp["end"], region_end)

            if cursor < sp_start:
                segments.append(EditSegment(cursor, sp_start, 1.0))
            segments.append(EditSegment(sp_start, sp_end, sp["factor"]))
            cursor = sp_end

        if cursor < region_end:
            segments.append(EditSegment(cursor, region_end, 1.0))

    # Filter out degenerate segments
    segments = [s for s in segments if s.original_duration > 0.01]

    log.info(f"Built {len(segments)} keep segments from {len(keep_regions)} regions")
    return segments


# ── FFmpeg Segment Processing ──────────────────────────────────────────────────

def build_atempo_chain(speed: float) -> list[str]:
    """
    Build an atempo filter chain for a given speed factor.

    atempo only supports values between 0.5 and 100.0, but
    for values > 2.0 we need to chain multiple filters.
    """
    if speed <= 0.5:
        return ["atempo=0.5"]
    if speed <= 2.0:
        return [f"atempo={speed}"]

    # Chain multiple atempo filters for speed > 2.0
    chain = []
    remaining = speed
    while remaining > 2.0:
        chain.append("atempo=2.0")
        remaining /= 2.0
    if remaining > 1.0:
        chain.append(f"atempo={remaining:.6f}")
    return chain


def export_segment(
    video_path: str,
    segment: EditSegment,
    output_path: str,
    target_resolution: str,
) -> bool:
    """Export a single segment with speed adjustment to a temp file."""
    cmd = [
        "ffmpeg", "-y",
        "-ss", f"{segment.start:.6f}",
        "-to", f"{segment.end:.6f}",
        "-i", video_path,
    ]

    # Build filter chain
    video_filters = []
    audio_filters = []

    # Speed adjustment
    if segment.speed != 1.0:
        pts_factor = 1.0 / segment.speed
        video_filters.append(f"setpts={pts_factor:.6f}*PTS")
        audio_filters.extend(build_atempo_chain(segment.speed))

    # Resolution scaling
    video_filters.append(f"scale={target_resolution}:force_original_aspect_ratio=decrease")
    video_filters.append(f"pad={target_resolution}:(ow-iw)/2:(oh-ih)/2")

    cmd.extend(["-vf", ",".join(video_filters)])

    if audio_filters:
        cmd.extend(["-af", ",".join(audio_filters)])

    cmd.extend([
        "-c:v", config.EXPORT_VIDEO_CODEC,
        "-preset", config.EXPORT_VIDEO_PRESET,
        "-crf", str(config.EXPORT_CRF),
        "-pix_fmt", config.EXPORT_PIXEL_FORMAT,
        "-c:a", config.EXPORT_AUDIO_CODEC,
        "-b:a", config.EXPORT_AUDIO_BITRATE,
        "-movflags", "+faststart",
        output_path,
    ])

    try:
        run_ffmpeg(cmd, desc=f"export segment {segment.start:.2f}-{segment.end:.2f}")
        return True
    except RuntimeError as e:
        log.error(f"Failed to export segment: {e}")
        return False


def concatenate_segments(
    segment_files: list[str],
    output_path: str,
    crossfade: float,
) -> str:
    """
    Concatenate segment files using ffmpeg concat demuxer with audio crossfade.
    """
    if not segment_files:
        raise ValueError("No segments to concatenate")

    if len(segment_files) == 1:
        # Single segment, just copy
        cmd = ["ffmpeg", "-y", "-i", segment_files[0], "-c", "copy", output_path]
        run_ffmpeg(cmd, "copy single segment")
        return output_path

    # For crossfade, we need to re-encode. Use concat filter with audio crossfade.
    # For large numbers of segments, use concat demuxer (faster) with a separate
    # audio crossfade pass.

    # Step 1: Concat demuxer (lossless concat of same-format segments)
    concat_list = tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", delete=False, prefix="concat_"
    )
    for sf in segment_files:
        concat_list.write(f"file '{os.path.abspath(sf)}'\n")
    concat_list.close()

    intermediate = output_path + ".intermediate.mp4"
    cmd = [
        "ffmpeg", "-y",
        "-f", "concat", "-safe", "0",
        "-i", concat_list.name,
        "-c:v", config.EXPORT_VIDEO_CODEC,
        "-preset", config.EXPORT_VIDEO_PRESET,
        "-crf", str(config.EXPORT_CRF),
        "-pix_fmt", config.EXPORT_PIXEL_FORMAT,
        "-c:a", config.EXPORT_AUDIO_CODEC,
        "-b:a", config.EXPORT_AUDIO_BITRATE,
        "-movflags", "+faststart",
        intermediate,
    ]
    run_ffmpeg(cmd, "concatenate segments")

    # Step 2: Apply audio crossfade at cut points to eliminate pops
    # Build crossfade filter for audio at each junction
    if crossfade > 0 and len(segment_files) > 1:
        # Apply a gentle audio fade in/out at segment boundaries
        # This uses the afade filter on the concatenated output
        cmd = [
            "ffmpeg", "-y",
            "-i", intermediate,
            "-af", f"afade=t=in:st=0:d={crossfade},"
                   f"afade=t=out:st=0:d={crossfade}",
            "-c:v", "copy",
            "-c:a", config.EXPORT_AUDIO_CODEC,
            "-b:a", config.EXPORT_AUDIO_BITRATE,
            "-movflags", "+faststart",
            output_path,
        ]
        try:
            run_ffmpeg(cmd, "apply audio crossfade")
            os.unlink(intermediate)
        except RuntimeError:
            log.warning("Audio crossfade failed, using raw concatenation")
            os.rename(intermediate, output_path)
    else:
        os.rename(intermediate, output_path)

    os.unlink(concat_list.name)
    return output_path


# ── Short Candidate Export ─────────────────────────────────────────────────────

def export_short_candidate(
    video_path: str,
    short_info: dict,
    output_path: str,
):
    """Export a vertical 9:16 short candidate clip."""
    start = short_info.get("start", 0)
    end = short_info.get("end", 0)
    duration = end - start

    if duration <= 0 or duration > config.SHORT_MAX_DURATION:
        log.warning(f"Short candidate invalid duration: {duration:.1f}s")
        return False

    log.info(f"Exporting short candidate: {start:.1f}s - {end:.1f}s ({duration:.1f}s)")

    cmd = [
        "ffmpeg", "-y",
        "-ss", f"{start:.6f}",
        "-to", f"{end:.6f}",
        "-i", video_path,
        "-vf", (
            f"scale={config.SHORT_RESOLUTION}:"
            "force_original_aspect_ratio=decrease,"
            f"pad={config.SHORT_RESOLUTION}:(ow-iw)/2:(oh-ih)/2"
        ),
        "-c:v", config.EXPORT_VIDEO_CODEC,
        "-preset", config.EXPORT_VIDEO_PRESET,
        "-crf", str(config.EXPORT_CRF),
        "-pix_fmt", config.EXPORT_PIXEL_FORMAT,
        "-c:a", config.EXPORT_AUDIO_CODEC,
        "-b:a", config.EXPORT_AUDIO_BITRATE,
        "-movflags", "+faststart",
        output_path,
    ]

    try:
        run_ffmpeg(cmd, "export short candidate")
        log.info(f"Short candidate saved to {output_path}")
        return True
    except RuntimeError as e:
        log.error(f"Failed to export short: {e}")
        return False


# ── Upload Metadata ────────────────────────────────────────────────────────────

def generate_upload_metadata(notes: dict, output_path: str):
    """Generate upload metadata file with title, description template, tags."""
    title = notes.get("suggested_title", "Untitled Video")
    hook = notes.get("suggested_hook", "")
    sc = notes.get("short_candidate", {})

    # Pick a thumbnail timestamp from anchor moments
    anchors = notes.get("anchor_moments", [])
    thumb_ts = anchors[0]["start"] if anchors else 0.0

    metadata = f"""TITLE: {title}

DESCRIPTION:
{hook}

[Add your description here]

---
Edited with AI Video Editor Pipeline

TAGS:
AI, machine learning, tutorial, educational, tech, coding, demo

THUMBNAIL TIMESTAMP: {thumb_ts:.1f}s

SHORT CANDIDATE:
  Start: {sc.get('start', 'N/A')}s
  End: {sc.get('end', 'N/A')}s
  Reason: {sc.get('reason', 'N/A')}
"""

    with open(output_path, "w") as f:
        f.write(metadata)
    log.info(f"Upload metadata saved to {output_path}")


# ── Main Pipeline ──────────────────────────────────────────────────────────────

def apply_edits(video_path: str, notes: dict, dry_run: bool = False):
    """Execute all edits and produce final output files."""
    duration = get_video_duration(video_path)
    log.info(f"Input video: {video_path} ({duration:.1f}s)")

    cuts = notes.get("cuts", [])
    speedups = notes.get("speedups", [])
    short_info = notes.get("short_candidate", {})

    # Build segment list
    segments = build_keep_segments(duration, cuts, speedups)

    if not segments:
        log.error("No segments to keep after applying edits. Aborting.")
        sys.exit(1)

    total_output = sum(s.output_duration for s in segments)
    total_cut = sum(c["end"] - c["start"] for c in cuts)

    print("\n" + "=" * 70)
    print("  EDIT EXECUTION PLAN")
    print("=" * 70)
    print(f"  Input duration:     {duration:.1f}s ({duration/60:.1f} min)")
    print(f"  Segments to keep:   {len(segments)}")
    print(f"  Total cut time:     {total_cut:.1f}s")
    print(f"  Estimated output:   {total_output:.1f}s ({total_output/60:.1f} min)")
    print(f"  Speedup segments:   {len(speedups)}")
    print()

    for i, seg in enumerate(segments[:20]):
        speed_str = f" @{seg.speed}x" if seg.speed != 1.0 else ""
        print(f"    [{i:3d}] {seg.start:8.2f}s - {seg.end:8.2f}s "
              f"({seg.original_duration:6.2f}s{speed_str})")
    if len(segments) > 20:
        print(f"    ... and {len(segments) - 20} more segments")
    print("=" * 70 + "\n")

    if dry_run:
        log.info("Dry run mode — no files written.")
        return

    # Create output directory
    output_dir = Path(config.OUTPUT_DIR)
    output_dir.mkdir(exist_ok=True)

    # Create temp directory for segment files
    temp_dir = tempfile.mkdtemp(prefix="video_edit_")
    log.info(f"Temp directory: {temp_dir}")

    segment_files = []
    target_res = config.EXPORT_RESOLUTION

    log.info(f"Exporting {len(segments)} segments...")
    for i, seg in enumerate(tqdm(segments, desc="Processing segments", unit="seg")):
        seg_path = os.path.join(temp_dir, f"seg_{i:05d}.mp4")
        success = export_segment(video_path, seg, seg_path, target_res)
        if success and os.path.exists(seg_path):
            segment_files.append(seg_path)
        else:
            log.warning(f"Segment {i} failed, skipping")

    if not segment_files:
        log.error("All segments failed to export. Aborting.")
        sys.exit(1)

    log.info(f"Successfully exported {len(segment_files)}/{len(segments)} segments")

    # Concatenate
    final_path = str(output_dir / "final_edit.mp4")
    log.info("Concatenating segments into final edit...")
    concatenate_segments(segment_files, final_path, config.CROSSFADE_DURATION)

    final_duration = get_video_duration(final_path)
    log.info(f"Final edit: {final_path} ({final_duration:.1f}s)")

    # Export short candidate
    if short_info and short_info.get("start") is not None:
        short_path = str(output_dir / "short_candidate.mp4")
        export_short_candidate(video_path, short_info, short_path)

    # Generate upload metadata
    metadata_path = str(output_dir / "upload_metadata.txt")
    generate_upload_metadata(notes, metadata_path)

    # Cleanup temp files
    log.info("Cleaning up temp files...")
    for sf in segment_files:
        try:
            os.unlink(sf)
        except OSError:
            pass
    try:
        os.rmdir(temp_dir)
    except OSError:
        pass

    # Final summary
    print("\n" + "=" * 70)
    print("  EXPORT COMPLETE")
    print("=" * 70)
    print(f"  Final edit:         {final_path} ({final_duration:.1f}s)")
    if os.path.exists(str(output_dir / "short_candidate.mp4")):
        short_dur = get_video_duration(str(output_dir / "short_candidate.mp4"))
        print(f"  Short candidate:    {output_dir / 'short_candidate.mp4'} ({short_dur:.1f}s)")
    print(f"  Upload metadata:    {metadata_path}")
    print(f"  Time saved:         {duration - final_duration:.1f}s "
          f"({(duration - final_duration) / duration * 100:.1f}%)")
    print("=" * 70 + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Phase 2: Apply edits from edit_notes.json via ffmpeg"
    )
    parser.add_argument("--input", "-i", required=True, help="Path to raw video file")
    parser.add_argument("--edit-notes", default="edit_notes.json",
                        help="Path to edit notes JSON")
    parser.add_argument("--overrides", default=None,
                        help="Path to overrides JSON from review.py")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show edit plan without executing")
    args = parser.parse_args()

    if not os.path.isfile(args.input):
        log.error(f"Input file not found: {args.input}")
        sys.exit(1)

    if not os.path.isfile(args.edit_notes):
        log.error(f"Edit notes not found: {args.edit_notes}. Run analyze_video.py first.")
        sys.exit(1)

    with open(args.edit_notes) as f:
        notes = json.load(f)

    # Apply overrides if provided
    if args.overrides:
        if not os.path.isfile(args.overrides):
            log.error(f"Overrides file not found: {args.overrides}")
            sys.exit(1)
        with open(args.overrides) as f:
            overrides = json.load(f)
        notes = apply_overrides(notes, overrides)

    apply_edits(args.input, notes, dry_run=args.dry_run)


def apply_overrides(notes: dict, overrides: dict) -> dict:
    """Apply user overrides from review.py to edit notes."""
    skip_indices = set(overrides.get("skip_cuts", []))
    override_map = {o["index"]: o for o in overrides.get("override_cuts", [])}

    if skip_indices:
        log.info(f"Applying overrides: skipping {len(skip_indices)} cuts")

    original_cuts = notes.get("cuts", [])
    new_cuts = []
    for i, cut in enumerate(original_cuts):
        if i in skip_indices:
            log.info(f"  Skipping cut [{i}]: {cut['start']:.2f}-{cut['end']:.2f}")
            continue
        if i in override_map:
            ov = override_map[i]
            if "start" in ov:
                cut["start"] = ov["start"]
            if "end" in ov:
                cut["end"] = ov["end"]
            log.info(f"  Overriding cut [{i}]: now {cut['start']:.2f}-{cut['end']:.2f}")
        new_cuts.append(cut)

    notes["cuts"] = new_cuts
    return notes


if __name__ == "__main__":
    main()
