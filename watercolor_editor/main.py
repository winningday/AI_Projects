"""
main.py — Watercolor Class Video Editor — CLI Entry Point

Usage:
    python main.py \\
        --angle-a footage/angle_a.mp4 \\
        --angle-b footage/angle_b.mp4 \\
        --angle-c footage/palette_cam.mp4 \\
        --reference footage/reference_photo.jpg \\
        --output output/final/class_01.mp4 \\
        --project "class_01"

    # Development mode (process first 5 minutes only):
    python main.py --angle-a ... --dev

    # Skip to a specific stage (requires previous stage outputs in output/):
    python main.py --angle-a ... --start-stage 2

Pipeline stages:
    0 — Sync & align camera timelines
    1 — Parallel analysis (vision + motion + audio)
    2 — Build Edit Decision List
    3 — Compose & render final video
    4 — Generate subtitle files
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from config import WatercolorEditorConfig, CameraConfig
from utils.ffmpeg_utils import (
    check_ffmpeg_available, check_ffprobe_available,
    get_video_duration, get_video_fps,
)

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# CLI argument parsing
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="AI-powered watercolor class video editor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    # Input files
    parser.add_argument("--angle-a", required=True,
                        help="Path to primary painting view (Angle A)")
    parser.add_argument("--angle-b",
                        help="Path to backup painting view (Angle B)")
    parser.add_argument("--angle-c",
                        help="Path to dedicated palette camera (Angle C — PiP lower-right)")
    parser.add_argument("--reference",
                        help="Path to reference photo (static image — PiP upper-right)")

    # Output
    parser.add_argument("--output", default="output/final/edited.mp4",
                        help="Output video path (default: output/final/edited.mp4)")
    parser.add_argument("--project", default="watercolor_class",
                        help="Project name used in file names and title cards")

    # Canvas ROI (optional — set if auto-detection is insufficient)
    parser.add_argument("--canvas-roi-a", type=float, nargs=4,
                        metavar=("X", "Y", "W", "H"),
                        help="Canvas ROI for angle A as fractions: x y w h (e.g. 0.05 0.10 0.65 0.80)")
    parser.add_argument("--canvas-roi-b", type=float, nargs=4,
                        metavar=("X", "Y", "W", "H"),
                        help="Canvas ROI for angle B as fractions")

    # Pipeline control
    parser.add_argument("--start-stage", type=int, default=0, choices=[0, 1, 2, 3, 4],
                        help="Resume from this stage (uses saved outputs from prior stages)")
    parser.add_argument("--dev", action="store_true",
                        help="Development mode: process only the first 5 minutes")
    parser.add_argument("--dev-duration", type=float, default=300.0,
                        help="Duration (seconds) to process in dev mode (default: 300)")

    # Logging
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Enable verbose (DEBUG) logging")

    return parser.parse_args()


# ---------------------------------------------------------------------------
# Pipeline runner
# ---------------------------------------------------------------------------

def run_pipeline(args: argparse.Namespace) -> None:
    # Build config from args
    cfg = WatercolorEditorConfig(
        project_name=args.project,
        dev_mode=args.dev,
        dev_mode_duration_sec=args.dev_duration,
        cameras=CameraConfig(
            angle_a_path=args.angle_a,
            angle_b_path=args.angle_b,
            angle_c_path=args.angle_c,
            reference_photo_path=args.reference,
        ),
    )

    if args.canvas_roi_a:
        cfg.vision.canvas_roi_a = tuple(args.canvas_roi_a)
    if args.canvas_roi_b:
        cfg.vision.canvas_roi_b = tuple(args.canvas_roi_b)

    # Set up output directories
    out_dir = Path("output")
    analysis_dir = out_dir / "analysis"
    analysis_dir.mkdir(parents=True, exist_ok=True)
    Path(cfg.render.temp_dir).mkdir(parents=True, exist_ok=True)
    Path(cfg.render.final_output_dir).mkdir(parents=True, exist_ok=True)

    angle_paths = {
        "a": args.angle_a,
        "b": args.angle_b,
        "c": args.angle_c,
    }

    start = args.start_stage

    # ------------------------------------------------------------------
    # Stage 0: Sync
    # ------------------------------------------------------------------
    offsets = {"a": 0.0, "b": 0.0, "c": 0.0}
    if start <= 0:
        log.info("=" * 60)
        log.info("STAGE 0: Sync & align camera timelines")
        log.info("=" * 60)
        from pipeline.stage0_sync import sync_angles
        offsets = sync_angles(cfg)
        import json
        with open(analysis_dir / "offsets.json", "w") as f:
            json.dump(offsets, f, indent=2)
        log.info(f"Sync offsets: {offsets}")
    else:
        import json
        offsets_path = analysis_dir / "offsets.json"
        if offsets_path.exists():
            with open(offsets_path) as f:
                offsets = json.load(f)
            log.info(f"Loaded sync offsets: {offsets}")

    # ------------------------------------------------------------------
    # Stage 1: Analysis (vision + motion + audio)
    # ------------------------------------------------------------------
    from models.segment import save_analysis_windows, load_analysis_windows

    transcripts = []
    windows = []

    if start <= 1:
        log.info("=" * 60)
        log.info("STAGE 1: Analysis (vision + motion + audio)")
        log.info("=" * 60)

        from pipeline.stage1a_vision import analyse_obstruction, select_angle_per_frame
        from pipeline.stage1b_motion import analyse_motion
        from pipeline.stage1c_audio import run_audio_pipeline
        from pipeline.stage2_edl import aggregate_windows

        primary_audio_angle = cfg.cameras.primary_audio_angle
        primary_path = angle_paths.get(primary_audio_angle) or args.angle_a

        # 1A: Vision analysis
        log.info("1A: Obstruction detection...")
        from models.segment import AngleID
        obs_a = analyse_obstruction(cfg, AngleID.A, args.angle_a,
                                     start_offset_sec=offsets.get("a", 0.0))
        obs_b = []
        if args.angle_b:
            obs_b = analyse_obstruction(cfg, AngleID.B, args.angle_b,
                                         start_offset_sec=offsets.get("b", 0.0))

        # 1B: Motion analysis
        log.info("1B: Motion scoring...")
        motion_a = analyse_motion(cfg, AngleID.A, args.angle_a,
                                   canvas_roi_frac=cfg.vision.canvas_roi_a,
                                   start_offset_sec=offsets.get("a", 0.0))

        # 1C: Audio pipeline
        log.info("1C: Transcription + classification + translation...")
        transcripts = run_audio_pipeline(cfg, primary_path,
                                          start_offset_sec=offsets.get(primary_audio_angle, 0.0))

        # Aggregate into windows
        fps = get_video_fps(args.angle_a)
        windows = aggregate_windows(
            motion_results_a=motion_a,
            obstruction_results_a=obs_a,
            obstruction_results_b=obs_b,
            transcripts=transcripts,
            fps=fps,
        )

        # Save analysis to disk
        import json, pickle
        save_analysis_windows(windows, str(analysis_dir / "windows.json"))
        with open(analysis_dir / "transcripts.pkl", "wb") as f:
            pickle.dump(transcripts, f)
        log.info(f"Analysis saved: {len(windows)} windows, {len(transcripts)} transcript segments")

    else:
        import json, pickle
        windows_path = analysis_dir / "windows.json"
        transcripts_path = analysis_dir / "transcripts.pkl"
        if windows_path.exists():
            windows = load_analysis_windows(str(windows_path))
        if transcripts_path.exists():
            with open(transcripts_path, "rb") as f:
                transcripts = pickle.load(f)
        log.info(f"Loaded: {len(windows)} windows, {len(transcripts)} transcript segments")

    # ------------------------------------------------------------------
    # Stage 2: Build EDL
    # ------------------------------------------------------------------
    from models.edl import EditDecisionList

    edl = None
    if start <= 2:
        log.info("=" * 60)
        log.info("STAGE 2: Building Edit Decision List")
        log.info("=" * 60)
        from pipeline.stage2_edl import build_edl

        source_duration = get_video_duration(args.angle_a)
        edl = build_edl(cfg, windows, transcripts, source_duration)
        edl.save(str(analysis_dir / "edl.json"))
        log.info(f"EDL saved: {len(edl.entries)} entries")
    else:
        edl_path = analysis_dir / "edl.json"
        if edl_path.exists():
            edl = EditDecisionList.load(str(edl_path))
            log.info(f"Loaded EDL: {len(edl.entries)} entries")
        else:
            log.error("EDL file not found. Run from stage 2 or earlier.")
            sys.exit(1)

    # ------------------------------------------------------------------
    # Stage 3: Render
    # ------------------------------------------------------------------
    if start <= 3:
        log.info("=" * 60)
        log.info("STAGE 3: Composing & rendering final video")
        log.info("=" * 60)
        from pipeline.stage3_compose import render

        # Subtitle file path (from stage 4 if it ran before; otherwise None)
        sub_path = str(analysis_dir / f"{cfg.project_name}.ass")
        if not Path(sub_path).exists():
            sub_path = None

        render(
            config=cfg,
            edl=edl,
            angle_paths=angle_paths,
            reference_photo_path=args.reference,
            subtitle_path=sub_path,
            output_path=args.output,
        )

    # ------------------------------------------------------------------
    # Stage 4: Subtitle files
    # ------------------------------------------------------------------
    if start <= 4:
        log.info("=" * 60)
        log.info("STAGE 4: Generating subtitle files")
        log.info("=" * 60)
        from pipeline.stage4_subtitles import generate_subtitles

        # Collect all subtitles from EDL entries (they have adjusted timestamps)
        all_subs = []
        for entry in edl.entries:
            all_subs.extend(entry.subtitles)

        # Sort by start time
        all_subs.sort(key=lambda s: s.start_sec)

        paths = generate_subtitles(
            segments=all_subs,
            output_dir=str(analysis_dir),
            project_name=cfg.project_name,
        )
        log.info(f"Subtitle files: {paths}")

        # If rendering already happened without subtitles, re-render with them
        if start <= 3 and paths.get("ass"):
            log.info("Re-rendering with subtitles burned in...")
            import shutil
            from pipeline.stage3_compose import _burn_subtitles, _run_ffmpeg
            composed_path = str(Path(args.output).with_suffix("")) + "_no_subs.mp4"
            shutil.move(args.output, composed_path)
            _burn_subtitles(composed_path, paths["ass"], args.output, cfg)
            Path(composed_path).unlink(missing_ok=True)

    log.info("=" * 60)
    log.info(f"Done. Output: {args.output}")
    log.info("=" * 60)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    args = parse_args()

    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )

    # Pre-flight checks
    if not check_ffmpeg_available():
        log.error("FFmpeg not found. Install FFmpeg and ensure it is on your PATH.")
        sys.exit(1)
    if not check_ffprobe_available():
        log.error("ffprobe not found. Install FFmpeg (includes ffprobe).")
        sys.exit(1)

    if not Path(args.angle_a).exists():
        log.error(f"Angle A file not found: {args.angle_a}")
        sys.exit(1)

    if args.dev:
        log.info(
            f"DEV MODE: Processing first {args.dev_duration:.0f}s of footage only."
        )

    run_pipeline(args)


if __name__ == "__main__":
    main()
