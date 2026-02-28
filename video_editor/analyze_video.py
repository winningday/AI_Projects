#!/usr/bin/env python3
"""
Phase 1: Multimodal Video Analysis Pipeline

Analyzes raw video using BOTH audio transcription (Whisper) and
visual frame analysis (Claude Vision) to produce unified edit notes.

Usage:
    python analyze_video.py --input raw_video.mp4
    python analyze_video.py --input raw_video.mp4 --mode accuracy
    python analyze_video.py --input raw_video.mp4 --skip-transcription  # reuse existing transcript
    python analyze_video.py --input raw_video.mp4 --skip-vision        # reuse existing vision data
"""

import argparse
import base64
import json
import logging
import math
import os
import subprocess
import sys
import time
from pathlib import Path

from tqdm import tqdm

import config

# ── Logging Setup ──────────────────────────────────────────────────────────────

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
    """Get video duration in seconds using ffprobe."""
    cmd = [
        "ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_format",
        video_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    info = json.loads(result.stdout)
    duration = float(info["format"]["duration"])
    log.info(f"Video duration: {duration:.2f}s ({duration/60:.1f} min)")
    return duration


def get_video_resolution(video_path: str) -> tuple[int, int]:
    """Get video width and height."""
    cmd = [
        "ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_streams",
        "-select_streams", "v:0",
        video_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    streams = json.loads(result.stdout)["streams"]
    if not streams:
        raise ValueError("No video stream found")
    w = int(streams[0]["width"])
    h = int(streams[0]["height"])
    log.info(f"Video resolution: {w}x{h}")
    return w, h


def validate_dependencies():
    """Check that required external tools are available."""
    for tool in ["ffmpeg", "ffprobe"]:
        result = subprocess.run(["which", tool], capture_output=True)
        if result.returncode != 0:
            log.error(f"Required tool '{tool}' not found. Install ffmpeg.")
            sys.exit(1)
    log.info("All external dependencies found.")


# ── Step 1A: Transcription ────────────────────────────────────────────────────

def transcribe_video(video_path: str, mode: str = "fast") -> list[dict]:
    """
    Transcribe video with openai-whisper, word-level timestamps.

    Returns list of {word, start, end, confidence} dicts.
    """
    import whisper

    model_name = config.WHISPER_MODEL_ACCURACY if mode == "accuracy" else config.WHISPER_MODEL_FAST
    log.info(f"Loading Whisper model: {model_name} (mode={mode})")
    model = whisper.load_model(model_name)

    log.info("Transcribing audio (this may take a while for long videos)...")
    result = model.transcribe(
        video_path,
        word_timestamps=True,
        verbose=False,
    )

    words = []
    for segment in result.get("segments", []):
        for w in segment.get("words", []):
            words.append({
                "word": w["word"].strip(),
                "start": round(w["start"], 3),
                "end": round(w["end"], 3),
                "confidence": round(w.get("probability", 0.0), 4),
            })

    log.info(f"Transcription complete: {len(words)} words extracted.")
    return words


def save_transcript(words: list[dict], output_path: str = "transcript.json"):
    """Save transcript to JSON."""
    with open(output_path, "w") as f:
        json.dump(words, f, indent=2)
    log.info(f"Transcript saved to {output_path}")


# ── Step 1B: Frame Sampling ───────────────────────────────────────────────────

def detect_scene_changes(video_path: str) -> list[float]:
    """
    Detect scene-change timestamps using ffmpeg's scene filter.

    Returns list of timestamps (seconds) where scene changes occur.
    """
    log.info("Detecting scene changes...")
    cmd = [
        "ffmpeg", "-i", video_path,
        "-vf", f"select='gt(scene,{config.SCENE_CHANGE_THRESHOLD})',showinfo",
        "-vsync", "vfr",
        "-f", "null", "-",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)

    timestamps = []
    for line in result.stderr.split("\n"):
        if "pts_time:" in line:
            try:
                pts_part = line.split("pts_time:")[1].split()[0]
                ts = float(pts_part)
                timestamps.append(round(ts, 3))
            except (IndexError, ValueError):
                continue

    log.info(f"Detected {len(timestamps)} scene changes.")
    return timestamps


def extract_frames(video_path: str, duration: float) -> dict:
    """
    Extract frames at regular intervals + extra frames near scene changes.

    Returns frame index: {timestamp_str: filepath}
    """
    frames_dir = Path(config.FRAMES_DIR)
    frames_dir.mkdir(exist_ok=True)

    # Get scene change timestamps for high-motion sampling
    scene_changes = detect_scene_changes(video_path)
    scene_set = set()
    for sc in scene_changes:
        # Sample every 1s in a ±2s window around each scene change
        for offset in [-2, -1, 0, 1, 2]:
            t = round(sc + offset, 1)
            if 0 <= t <= duration:
                scene_set.add(t)

    # Build unified sample list: every 3s + scene-change 1s samples
    sample_times = set()
    t = 0.0
    while t <= duration:
        sample_times.add(round(t, 3))
        t += config.FRAME_INTERVAL_NORMAL
    sample_times.update(scene_set)
    sample_times = sorted(sample_times)

    log.info(f"Extracting {len(sample_times)} frames...")
    frame_index = {}

    for ts in tqdm(sample_times, desc="Extracting frames", unit="frame"):
        filename = f"frame_{ts:09.3f}.jpg"
        filepath = str(frames_dir / filename)

        cmd = [
            "ffmpeg", "-y",
            "-ss", str(ts),
            "-i", video_path,
            "-vframes", "1",
            "-q:v", str(max(2, 31 - int(config.FRAME_JPEG_QUALITY / 3.5))),
            filepath,
        ]
        subprocess.run(cmd, capture_output=True, check=False)

        if os.path.exists(filepath):
            frame_index[f"{ts:.3f}"] = filepath
        else:
            log.warning(f"Failed to extract frame at {ts:.3f}s")

    log.info(f"Extracted {len(frame_index)} frames to {frames_dir}/")

    # Save frame index
    with open("frame_index.json", "w") as f:
        json.dump(frame_index, f, indent=2)
    log.info("Frame index saved to frame_index.json")

    return frame_index


# ── Step 1C: Vision Analysis ──────────────────────────────────────────────────

VISION_SYSTEM_PROMPT = """You are analyzing frames from a raw YouTube recording of educational AI content. For each frame, identify:

1. VISUAL QUALITY FLAGS:
   - Screen clutter (too many windows, disorganized desktop)
   - Bad framing (webcam off-center, poor lighting, distracting background)
   - Loading/waiting states (spinners, blank screens, progress bars)
   - Redundant screen content (same static screen held too long)
   - Errors or embarrassing UI states the creator wouldn't want shown

2. CONTENT SIGNAL:
   - Is a demo actively happening? (code running, UI interaction, tool being used)
   - Is this a talking-head moment? (presenter explaining, no screen action)
   - Is this a transition? (switching tabs, opening apps, navigating menus)
   - Is this a high-value moment? (result appearing, aha moment, key output shown)

3. PACING SIGNAL:
   - Static screens held >5s with no change = speed up candidate
   - Rapid meaningful change = preserve at normal speed
   - Loading/setup sequences = 2x speed candidate

Return a JSON array where each element corresponds to one frame, in order:
{
  "timestamp": <float>,
  "quality_flag": <string or null>,
  "content_type": <string>,
  "pacing_signal": <string>,
  "note": <string>
}

quality_flag values: "clutter", "bad_framing", "loading", "redundant", "error", or null
content_type values: "demo", "talking_head", "transition", "high_value", "setup"
pacing_signal values: "speed_up", "preserve", "cut_candidate"

Return ONLY the JSON array, no other text."""


def encode_frame_base64(filepath: str) -> str:
    """Read and base64-encode a frame image, resizing if needed."""
    from PIL import Image
    import io

    img = Image.open(filepath)

    # Resize if exceeds max dimensions
    max_w, max_h = config.VISION_MAX_IMAGE_SIZE
    if img.width > max_w or img.height > max_h:
        ratio = min(max_w / img.width, max_h / img.height)
        new_size = (int(img.width * ratio), int(img.height * ratio))
        img = img.resize(new_size, Image.LANCZOS)

    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=80)
    return base64.standard_b64encode(buf.getvalue()).decode("utf-8")


def analyze_frames_batch(
    batch: list[tuple[str, str]],
    client,
) -> list[dict]:
    """
    Send a batch of (timestamp, filepath) pairs to Claude Vision.

    Returns list of per-frame analysis dicts.
    """
    content = []
    for ts_str, filepath in batch:
        b64 = encode_frame_base64(filepath)
        content.append({
            "type": "text",
            "text": f"Frame at timestamp {ts_str}s:",
        })
        content.append({
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": "image/jpeg",
                "data": b64,
            },
        })

    content.append({
        "type": "text",
        "text": f"Analyze all {len(batch)} frames above. Return a JSON array with one object per frame, in order.",
    })

    for attempt in range(config.VISION_MAX_RETRIES):
        try:
            response = client.messages.create(
                model=config.CLAUDE_MODEL,
                max_tokens=4096,
                system=VISION_SYSTEM_PROMPT,
                messages=[{"role": "user", "content": content}],
            )
            text = response.content[0].text.strip()

            # Extract JSON from response (handle markdown code blocks)
            if text.startswith("```"):
                lines = text.split("\n")
                text = "\n".join(lines[1:-1])
            results = json.loads(text)

            if isinstance(results, dict):
                results = [results]

            log.info(f"  Vision batch returned {len(results)} frame analyses.")
            return results

        except json.JSONDecodeError as e:
            log.warning(f"  Failed to parse vision response as JSON (attempt {attempt+1}): {e}")
            log.debug(f"  Raw response: {text[:500]}")
            if attempt < config.VISION_MAX_RETRIES - 1:
                time.sleep(config.VISION_RETRY_BASE_DELAY * (2 ** attempt))
            else:
                log.error("  Max retries exceeded for JSON parse. Returning empty batch.")
                return []

        except Exception as e:
            error_str = str(e).lower()
            if "rate" in error_str or "429" in error_str or "overloaded" in error_str:
                wait = config.VISION_RETRY_BASE_DELAY * (2 ** attempt)
                log.warning(f"  Rate limited. Waiting {wait:.1f}s (attempt {attempt+1})...")
                time.sleep(wait)
            else:
                log.error(f"  Vision API error: {e}")
                if attempt < config.VISION_MAX_RETRIES - 1:
                    time.sleep(config.VISION_RETRY_BASE_DELAY * (2 ** attempt))
                else:
                    log.error("  Max retries exceeded. Returning empty batch.")
                    return []

    return []


def run_vision_analysis(frame_index: dict) -> list[dict]:
    """
    Run Claude Vision analysis on all extracted frames.

    Processes in batches of VISION_BATCH_SIZE.
    """
    import anthropic

    if not config.ANTHROPIC_API_KEY:
        log.error("ANTHROPIC_API_KEY not set. Cannot run vision analysis.")
        sys.exit(1)

    client = anthropic.Anthropic(api_key=config.ANTHROPIC_API_KEY)

    sorted_items = sorted(frame_index.items(), key=lambda x: float(x[0]))
    total_frames = len(sorted_items)
    batch_count = math.ceil(total_frames / config.VISION_BATCH_SIZE)

    log.info(f"Running vision analysis: {total_frames} frames in {batch_count} batches")

    all_results = []
    for i in tqdm(range(0, total_frames, config.VISION_BATCH_SIZE),
                  desc="Vision analysis", unit="batch"):
        batch = sorted_items[i:i + config.VISION_BATCH_SIZE]
        log.info(f"Processing vision batch {i // config.VISION_BATCH_SIZE + 1}/{batch_count} "
                 f"({len(batch)} frames)")
        results = analyze_frames_batch(batch, client)
        all_results.extend(results)

    log.info(f"Vision analysis complete: {len(all_results)} frame analyses.")
    return all_results


def save_vision_analysis(results: list[dict], output_path: str = "vision_analysis.json"):
    """Save vision analysis results to JSON."""
    with open(output_path, "w") as f:
        json.dump(results, f, indent=2)
    log.info(f"Vision analysis saved to {output_path}")


# ── Step 1D: Unified Edit Decision ────────────────────────────────────────────

EDITOR_SYSTEM_PROMPT = """You are a world-class YouTube video editor specializing in educational AI/tech content. You edit like the best creators in this space -- fast-paced, zero fluff, high retention. You have TWO data sources: a full word-level transcript and a frame-by-frame visual analysis. Use both.

EDITING PHILOSOPHY:
- Hook in first 10 seconds. Re-engage every 60-90 seconds.
- Cut dead air, filler words, false starts, repeated sentences, pauses >0.8s
- Speed up: loading screens, setup/navigation sequences, typing-heavy moments with no narration (1.5x-2x)
- Preserve: core explanations, live demos with narration, key results, punchlines, aha moments
- Never cut a moment where the visual AND audio are both high-value simultaneously
- If audio says something important but visual is clutter, flag for b-roll note (do not cut audio)
- If visual shows a high-value result but audio is filler, preserve visual, tighten audio around it
- Pattern interrupts every 60-90s to reset attention

VISUAL-SPECIFIC RULES:
- Flag any segment where quality_flag = 'bad_framing' or 'error' for removal if audio is also weak
- Speed up all contiguous segments where content_type = 'loading' or 'setup'
- Mark high_value frames as anchor points -- build cuts around them, not through them
- If a static screen persists for 5+ seconds with no meaningful visual change, speed to 1.5x minimum

OUTPUT FORMAT — return ONLY valid JSON, no other text:
{
  "cuts": [{"start": <float>, "end": <float>, "reason": "<string>", "signal": "<audio|visual|both>"}],
  "speedups": [{"start": <float>, "end": <float>, "factor": <float>, "reason": "<string>"}],
  "anchor_moments": [{"start": <float>, "end": <float>, "description": "<string>"}],
  "broll_flags": [{"start": <float>, "end": <float>, "note": "<string>"}],
  "suggested_title": "<string>",
  "suggested_hook": "<string>",
  "short_candidate": {"start": <float>, "end": <float>, "reason": "<string>"},
  "pacing_notes": "<string>",
  "estimated_final_length_minutes": <float>
}"""


def generate_edit_notes(
    transcript_path: str,
    vision_path: str,
    video_duration: float,
) -> dict:
    """
    Send transcript + vision analysis to Claude for unified edit decisions.
    """
    import anthropic

    if not config.ANTHROPIC_API_KEY:
        log.error("ANTHROPIC_API_KEY not set.")
        sys.exit(1)

    with open(transcript_path) as f:
        transcript = json.load(f)
    with open(vision_path) as f:
        vision = json.load(f)

    # Truncate data for very long videos to stay within token limits
    # For transcripts over 50k words, summarize into segments
    transcript_text = json.dumps(transcript, indent=None)
    vision_text = json.dumps(vision, indent=None)

    user_message = f"""Here is the complete analysis data for a video that is {video_duration:.1f} seconds ({video_duration/60:.1f} minutes) long.

=== WORD-LEVEL TRANSCRIPT ===
{transcript_text}

=== FRAME-BY-FRAME VISUAL ANALYSIS ===
{vision_text}

Analyze both data sources together and produce the unified edit notes JSON. Remember:
- All timestamps must be between 0 and {video_duration:.1f}
- Cuts should not overlap with anchor_moments
- Speedup segments should not overlap with cuts
- The short_candidate must be ≤60 seconds long
- Be aggressive about cutting dead air and filler, but preserve all high-value content"""

    log.info("Sending transcript + vision data to Claude for edit decisions...")
    log.info(f"  Transcript: {len(transcript)} words, Vision: {len(vision)} frames")

    client = anthropic.Anthropic(api_key=config.ANTHROPIC_API_KEY)

    for attempt in range(config.VISION_MAX_RETRIES):
        try:
            response = client.messages.create(
                model=config.CLAUDE_MODEL,
                max_tokens=8192,
                system=EDITOR_SYSTEM_PROMPT,
                messages=[{"role": "user", "content": user_message}],
            )
            text = response.content[0].text.strip()

            # Extract JSON
            if text.startswith("```"):
                lines = text.split("\n")
                text = "\n".join(lines[1:-1])

            edit_notes = json.loads(text)
            log.info("Edit notes generated successfully.")
            return validate_edit_notes(edit_notes, video_duration)

        except json.JSONDecodeError as e:
            log.warning(f"Failed to parse edit notes JSON (attempt {attempt+1}): {e}")
            if attempt < config.VISION_MAX_RETRIES - 1:
                time.sleep(config.VISION_RETRY_BASE_DELAY * (2 ** attempt))
            else:
                log.error("Max retries for edit notes generation. Exiting.")
                sys.exit(1)

        except Exception as e:
            error_str = str(e).lower()
            if "rate" in error_str or "429" in error_str or "overloaded" in error_str:
                wait = config.VISION_RETRY_BASE_DELAY * (2 ** attempt)
                log.warning(f"Rate limited. Waiting {wait:.1f}s...")
                time.sleep(wait)
            else:
                log.error(f"API error generating edit notes: {e}")
                if attempt < config.VISION_MAX_RETRIES - 1:
                    time.sleep(config.VISION_RETRY_BASE_DELAY * (2 ** attempt))
                else:
                    sys.exit(1)

    sys.exit(1)


def validate_edit_notes(notes: dict, duration: float) -> dict:
    """Validate and clamp all timestamps against actual video duration."""
    def clamp(t: float) -> float:
        return max(0.0, min(t, duration))

    # Validate cuts
    valid_cuts = []
    for cut in notes.get("cuts", []):
        cut["start"] = clamp(cut["start"])
        cut["end"] = clamp(cut["end"])
        if cut["end"] - cut["start"] >= config.MIN_CUT_DURATION:
            valid_cuts.append(cut)
        else:
            log.debug(f"Skipping cut too short: {cut['start']:.3f}-{cut['end']:.3f}")
    notes["cuts"] = valid_cuts

    # Validate speedups
    valid_speedups = []
    for sp in notes.get("speedups", []):
        sp["start"] = clamp(sp["start"])
        sp["end"] = clamp(sp["end"])
        sp["factor"] = max(1.0, min(sp["factor"], config.MAX_SPEEDUP_FACTOR))
        if sp["end"] > sp["start"]:
            valid_speedups.append(sp)
    notes["speedups"] = valid_speedups

    # Validate anchor moments
    for am in notes.get("anchor_moments", []):
        am["start"] = clamp(am["start"])
        am["end"] = clamp(am["end"])

    # Ensure cuts don't overlap anchor moments
    anchors = notes.get("anchor_moments", [])
    if anchors:
        filtered_cuts = []
        for cut in notes["cuts"]:
            overlaps_anchor = False
            for anchor in anchors:
                if cut["start"] < anchor["end"] and cut["end"] > anchor["start"]:
                    overlaps_anchor = True
                    log.debug(f"Removing cut {cut['start']:.2f}-{cut['end']:.2f} "
                              f"(overlaps anchor {anchor['start']:.2f}-{anchor['end']:.2f})")
                    break
            if not overlaps_anchor:
                filtered_cuts.append(cut)
        notes["cuts"] = filtered_cuts

    # Validate short candidate
    sc = notes.get("short_candidate", {})
    if sc:
        sc["start"] = clamp(sc.get("start", 0))
        sc["end"] = clamp(sc.get("end", 0))
        if sc["end"] - sc["start"] > config.SHORT_MAX_DURATION:
            sc["end"] = sc["start"] + config.SHORT_MAX_DURATION

    # Validate broll flags
    for br in notes.get("broll_flags", []):
        br["start"] = clamp(br["start"])
        br["end"] = clamp(br["end"])

    log.info(f"Validated edit notes: {len(notes['cuts'])} cuts, "
             f"{len(notes['speedups'])} speedups, "
             f"{len(notes.get('anchor_moments', []))} anchors")
    return notes


def print_summary(notes: dict, original_duration: float):
    """Print a human-readable summary of edit decisions."""
    cut_time = sum(c["end"] - c["start"] for c in notes.get("cuts", []))
    speedup_segments = notes.get("speedups", [])

    # Estimate time saved from speedups
    speedup_saved = 0.0
    for sp in speedup_segments:
        original = sp["end"] - sp["start"]
        sped_up = original / sp["factor"]
        speedup_saved += original - sped_up

    total_saved = cut_time + speedup_saved
    estimated_final = original_duration - total_saved

    print("\n" + "=" * 70)
    print("  EDIT ANALYSIS SUMMARY")
    print("=" * 70)
    print(f"  Original duration:    {original_duration:.1f}s ({original_duration/60:.1f} min)")
    print(f"  Estimated final:      {estimated_final:.1f}s ({estimated_final/60:.1f} min)")
    print(f"  Content removed:      {cut_time:.1f}s ({cut_time/original_duration*100:.1f}%)")
    print(f"  Time saved (speedup): {speedup_saved:.1f}s")
    print(f"  Total time saved:     {total_saved:.1f}s ({total_saved/original_duration*100:.1f}%)")
    print(f"  Total cuts:           {len(notes.get('cuts', []))}")
    print(f"  Speedup segments:     {len(speedup_segments)}")
    print(f"  Anchor moments:       {len(notes.get('anchor_moments', []))}")
    print(f"  B-roll flags:         {len(notes.get('broll_flags', []))}")
    print()

    if notes.get("suggested_title"):
        print(f"  Suggested title: {notes['suggested_title']}")
    if notes.get("suggested_hook"):
        print(f"  Suggested hook:  {notes['suggested_hook']}")
    if notes.get("pacing_notes"):
        print(f"  Pacing notes:    {notes['pacing_notes']}")

    sc = notes.get("short_candidate", {})
    if sc and sc.get("start") is not None:
        sc_dur = sc.get("end", 0) - sc.get("start", 0)
        print(f"  Short candidate:  {sc['start']:.1f}s - {sc['end']:.1f}s "
              f"({sc_dur:.1f}s) — {sc.get('reason', '')}")

    print()

    # Signal distribution
    audio_cuts = sum(1 for c in notes.get("cuts", []) if c.get("signal") == "audio")
    visual_cuts = sum(1 for c in notes.get("cuts", []) if c.get("signal") == "visual")
    both_cuts = sum(1 for c in notes.get("cuts", []) if c.get("signal") == "both")
    print(f"  Cut signals: audio={audio_cuts}, visual={visual_cuts}, both={both_cuts}")
    print("=" * 70 + "\n")


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Phase 1: Multimodal video analysis for AI-powered editing"
    )
    parser.add_argument("--input", "-i", required=True, help="Path to raw video file")
    parser.add_argument("--mode", choices=["fast", "accuracy"], default="fast",
                        help="Whisper model: fast (base) or accuracy (large-v3)")
    parser.add_argument("--skip-transcription", action="store_true",
                        help="Skip transcription, reuse existing transcript.json")
    parser.add_argument("--skip-vision", action="store_true",
                        help="Skip vision analysis, reuse existing vision_analysis.json")
    parser.add_argument("--skip-frames", action="store_true",
                        help="Skip frame extraction, reuse existing frames/")
    parser.add_argument("--transcript", default="transcript.json",
                        help="Path to transcript JSON (default: transcript.json)")
    parser.add_argument("--vision-output", default="vision_analysis.json",
                        help="Path to vision analysis JSON")
    parser.add_argument("--edit-notes", default="edit_notes.json",
                        help="Path for output edit notes JSON")
    parser.add_argument("--dry-run", action="store_true",
                        help="Run analysis but don't call Claude APIs (requires existing data)")
    args = parser.parse_args()

    # Validate input
    if not os.path.isfile(args.input):
        log.error(f"Input file not found: {args.input}")
        sys.exit(1)

    validate_dependencies()

    video_path = args.input
    duration = get_video_duration(video_path)

    # ── Step 1A: Transcription ──
    if args.skip_transcription or args.dry_run:
        if not os.path.isfile(args.transcript):
            log.error(f"Transcript not found: {args.transcript}")
            sys.exit(1)
        log.info(f"Using existing transcript: {args.transcript}")
    else:
        log.info("=" * 50)
        log.info("STEP 1A: TRANSCRIPTION")
        log.info("=" * 50)
        words = transcribe_video(video_path, mode=args.mode)
        save_transcript(words, args.transcript)

    # ── Step 1B: Frame Sampling ──
    if args.skip_frames or args.skip_vision or args.dry_run:
        frame_index_path = "frame_index.json"
        if os.path.isfile(frame_index_path):
            with open(frame_index_path) as f:
                frame_index = json.load(f)
            log.info(f"Using existing frame index: {len(frame_index)} frames")
        elif not args.skip_vision and not args.dry_run:
            log.error("Frame index not found and frame extraction skipped.")
            sys.exit(1)
        else:
            frame_index = {}
    else:
        log.info("=" * 50)
        log.info("STEP 1B: FRAME SAMPLING")
        log.info("=" * 50)
        frame_index = extract_frames(video_path, duration)

    # ── Step 1C: Vision Analysis ──
    if args.skip_vision or args.dry_run:
        if not os.path.isfile(args.vision_output):
            log.error(f"Vision analysis not found: {args.vision_output}")
            sys.exit(1)
        log.info(f"Using existing vision analysis: {args.vision_output}")
    else:
        log.info("=" * 50)
        log.info("STEP 1C: VISION ANALYSIS")
        log.info("=" * 50)
        vision_results = run_vision_analysis(frame_index)
        save_vision_analysis(vision_results, args.vision_output)

    # ── Step 1D: Unified Edit Decision ──
    if args.dry_run:
        if os.path.isfile(args.edit_notes):
            log.info(f"Dry run: loading existing edit notes from {args.edit_notes}")
            with open(args.edit_notes) as f:
                edit_notes = json.load(f)
        else:
            log.info("Dry run: no existing edit notes found. Skipping edit decision.")
            return
    else:
        log.info("=" * 50)
        log.info("STEP 1D: UNIFIED EDIT DECISION")
        log.info("=" * 50)
        edit_notes = generate_edit_notes(args.transcript, args.vision_output, duration)

        with open(args.edit_notes, "w") as f:
            json.dump(edit_notes, f, indent=2)
        log.info(f"Edit notes saved to {args.edit_notes}")

    # ── Summary ──
    print_summary(edit_notes, duration)
    log.info("Phase 1 analysis complete.")


if __name__ == "__main__":
    main()
