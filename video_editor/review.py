#!/usr/bin/env python3
"""
Phase 3: Interactive Review Interface

Displays the edit plan from edit_notes.json and lets the user approve,
skip, or override individual cuts before executing the final edit.

Usage:
    python review.py
    python review.py --edit-notes custom_notes.json
    python review.py --input raw_video.mp4  # auto-runs apply_edits after review
"""

import argparse
import json
import logging
import os
import subprocess
import sys

import config

logging.basicConfig(
    level=getattr(logging, config.LOG_LEVEL),
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(config.LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger(__name__)


# ── Display Helpers ────────────────────────────────────────────────────────────

def fmt_time(seconds: float) -> str:
    """Format seconds as MM:SS.sss"""
    m = int(seconds // 60)
    s = seconds % 60
    return f"{m:02d}:{s:06.3f}"


def signal_color(signal: str) -> str:
    """Return ANSI color code for signal type."""
    colors = {
        "audio": "\033[94m",   # blue
        "visual": "\033[93m",  # yellow
        "both": "\033[91m",    # red
    }
    return colors.get(signal, "")


RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"


def print_header(title: str):
    print(f"\n{BOLD}{'=' * 70}")
    print(f"  {title}")
    print(f"{'=' * 70}{RESET}\n")


def print_overview(notes: dict, original_duration: float):
    """Print high-level edit statistics."""
    cuts = notes.get("cuts", [])
    speedups = notes.get("speedups", [])
    anchors = notes.get("anchor_moments", [])
    brolls = notes.get("broll_flags", [])

    cut_time = sum(c["end"] - c["start"] for c in cuts)
    speedup_saved = sum(
        (sp["end"] - sp["start"]) - (sp["end"] - sp["start"]) / sp["factor"]
        for sp in speedups
    )
    total_saved = cut_time + speedup_saved
    estimated_final = original_duration - total_saved

    print(f"  {BOLD}Original duration:{RESET}    {fmt_time(original_duration)} "
          f"({original_duration/60:.1f} min)")
    print(f"  {BOLD}Estimated final:{RESET}      {fmt_time(estimated_final)} "
          f"({estimated_final/60:.1f} min)")
    print(f"  {BOLD}Content removed:{RESET}      {fmt_time(cut_time)} "
          f"({cut_time/original_duration*100:.1f}%)")
    print(f"  {BOLD}Time saved (speed):{RESET}   {fmt_time(speedup_saved)}")
    print(f"  {BOLD}Total time saved:{RESET}     {fmt_time(total_saved)} "
          f"({total_saved/original_duration*100:.1f}%)")
    print()
    print(f"  Cuts: {BOLD}{len(cuts)}{RESET}  |  "
          f"Speedups: {BOLD}{len(speedups)}{RESET}  |  "
          f"Anchors: {BOLD}{len(anchors)}{RESET}  |  "
          f"B-roll flags: {BOLD}{len(brolls)}{RESET}")

    # Signal distribution
    audio = sum(1 for c in cuts if c.get("signal") == "audio")
    visual = sum(1 for c in cuts if c.get("signal") == "visual")
    both = sum(1 for c in cuts if c.get("signal") == "both")
    print(f"  Cut signals: audio={audio}, visual={visual}, both={both}")

    if notes.get("suggested_title"):
        print(f"\n  {CYAN}Title:{RESET} {notes['suggested_title']}")
    if notes.get("suggested_hook"):
        print(f"  {CYAN}Hook:{RESET}  {notes['suggested_hook']}")
    if notes.get("pacing_notes"):
        print(f"  {CYAN}Pacing:{RESET} {notes['pacing_notes']}")


def print_anchor_moments(notes: dict):
    """Display protected anchor moments."""
    anchors = notes.get("anchor_moments", [])
    if not anchors:
        print(f"  {DIM}No anchor moments defined.{RESET}")
        return

    print(f"  {GREEN}Protected anchor moments (will NOT be cut):{RESET}")
    for i, anchor in enumerate(anchors):
        dur = anchor["end"] - anchor["start"]
        print(f"    [{i:2d}] {fmt_time(anchor['start'])} - {fmt_time(anchor['end'])} "
              f"({dur:.1f}s) {DIM}{anchor.get('description', '')}{RESET}")


def print_cuts(notes: dict) -> list[dict]:
    """Display all cuts with details. Returns the cuts list."""
    cuts = notes.get("cuts", [])
    if not cuts:
        print(f"  {DIM}No cuts in edit plan.{RESET}")
        return cuts

    for i, cut in enumerate(cuts):
        dur = cut["end"] - cut["start"]
        sig = cut.get("signal", "unknown")
        color = signal_color(sig)
        print(f"  [{i:3d}] {fmt_time(cut['start'])} - {fmt_time(cut['end'])} "
              f"({dur:5.1f}s) {color}[{sig:6s}]{RESET} {DIM}{cut.get('reason', '')}{RESET}")
    return cuts


def print_speedups(notes: dict):
    """Display all speedup segments."""
    speedups = notes.get("speedups", [])
    if not speedups:
        print(f"  {DIM}No speedup segments.{RESET}")
        return

    for i, sp in enumerate(speedups):
        dur = sp["end"] - sp["start"]
        print(f"  [{i:2d}] {fmt_time(sp['start'])} - {fmt_time(sp['end'])} "
              f"({dur:5.1f}s) {YELLOW}@{sp['factor']}x{RESET} "
              f"{DIM}{sp.get('reason', '')}{RESET}")


def print_broll_flags(notes: dict):
    """Display b-roll flags."""
    brolls = notes.get("broll_flags", [])
    if not brolls:
        print(f"  {DIM}No b-roll flags.{RESET}")
        return

    for i, br in enumerate(brolls):
        dur = br["end"] - br["start"]
        print(f"  [{i:2d}] {fmt_time(br['start'])} - {fmt_time(br['end'])} "
              f"({dur:5.1f}s) {DIM}{br.get('note', '')}{RESET}")


# ── Interactive Review ─────────────────────────────────────────────────────────

def interactive_review(notes: dict) -> dict:
    """
    Let the user interactively approve, skip, or override individual cuts.

    Returns an overrides dict that can be passed to apply_edits.py.
    """
    cuts = notes.get("cuts", [])
    if not cuts:
        print("No cuts to review.")
        return {"skip_cuts": [], "override_cuts": []}

    print(f"\n{BOLD}INTERACTIVE CUT REVIEW{RESET}")
    print(f"For each cut, choose:")
    print(f"  {GREEN}[a]{RESET} Approve (keep this cut)")
    print(f"  {RED}[s]{RESET} Skip (remove this cut — keep the original content)")
    print(f"  {YELLOW}[o]{RESET} Override (adjust start/end times)")
    print(f"  {CYAN}[q]{RESET} Quit review (approve remaining cuts)")
    print(f"  {DIM}[p]{RESET} Preview context (show surrounding transcript)")
    print()

    skip_cuts = []
    override_cuts = []
    approved = 0
    skipped = 0
    overridden = 0

    # Load transcript for context if available
    transcript = None
    if os.path.isfile("transcript.json"):
        with open("transcript.json") as f:
            transcript = json.load(f)

    for i, cut in enumerate(cuts):
        dur = cut["end"] - cut["start"]
        sig = cut.get("signal", "unknown")
        color = signal_color(sig)

        print(f"\n{'─' * 60}")
        print(f"  Cut [{i:3d}/{len(cuts)-1}]  "
              f"{fmt_time(cut['start'])} → {fmt_time(cut['end'])}  "
              f"({dur:.1f}s)  {color}[{sig}]{RESET}")
        print(f"  Reason: {cut.get('reason', 'No reason given')}")

        while True:
            try:
                choice = input(f"  Action [a/s/o/q/p]: ").strip().lower()
            except (EOFError, KeyboardInterrupt):
                print("\n  Review cancelled.")
                choice = "q"

            if choice == "a" or choice == "":
                approved += 1
                break
            elif choice == "s":
                skip_cuts.append(i)
                skipped += 1
                print(f"  {RED}→ Skipped{RESET}")
                break
            elif choice == "o":
                try:
                    new_start = input(f"    New start [{cut['start']:.3f}]: ").strip()
                    new_end = input(f"    New end [{cut['end']:.3f}]: ").strip()
                    ov = {"index": i}
                    if new_start:
                        ov["start"] = float(new_start)
                    if new_end:
                        ov["end"] = float(new_end)
                    override_cuts.append(ov)
                    overridden += 1
                    print(f"  {YELLOW}→ Overridden{RESET}")
                except ValueError:
                    print("  Invalid number, try again.")
                    continue
                break
            elif choice == "q":
                remaining = len(cuts) - i
                print(f"  Auto-approving remaining {remaining} cuts.")
                approved += remaining
                break
            elif choice == "p":
                if transcript:
                    # Show words in a window around this cut
                    window = 2.0  # seconds before/after
                    context_words = [
                        w for w in transcript
                        if w["start"] >= cut["start"] - window
                        and w["end"] <= cut["end"] + window
                    ]
                    if context_words:
                        print(f"  {DIM}Transcript context "
                              f"({cut['start']-window:.1f}s - {cut['end']+window:.1f}s):{RESET}")
                        text = ""
                        for w in context_words:
                            in_cut = w["start"] >= cut["start"] and w["end"] <= cut["end"]
                            if in_cut:
                                text += f"{RED}{w['word']}{RESET} "
                            else:
                                text += f"{w['word']} "
                        print(f"    {text}")
                    else:
                        print("  No transcript words in this range.")
                else:
                    print("  No transcript.json found for context.")
                continue
            else:
                print("  Invalid choice. Use a/s/o/q/p.")
                continue

        if choice == "q":
            break

    # Summary
    print(f"\n{'─' * 60}")
    print(f"  {BOLD}Review complete:{RESET}")
    print(f"    Approved:  {GREEN}{approved}{RESET}")
    print(f"    Skipped:   {RED}{skipped}{RESET}")
    print(f"    Overridden: {YELLOW}{overridden}{RESET}")

    overrides = {
        "skip_cuts": skip_cuts,
        "override_cuts": override_cuts,
    }
    return overrides


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Phase 3: Interactive review of edit notes"
    )
    parser.add_argument("--edit-notes", default="edit_notes.json",
                        help="Path to edit notes JSON")
    parser.add_argument("--input", "-i", default=None,
                        help="Path to raw video (auto-runs apply_edits after review)")
    parser.add_argument("--no-interact", action="store_true",
                        help="Skip interactive review, just display the plan")
    args = parser.parse_args()

    if not os.path.isfile(args.edit_notes):
        log.error(f"Edit notes not found: {args.edit_notes}. Run analyze_video.py first.")
        sys.exit(1)

    with open(args.edit_notes) as f:
        notes = json.load(f)

    # Get original duration from video or estimate from edit notes
    original_duration = 0.0
    if args.input and os.path.isfile(args.input):
        cmd = [
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", args.input,
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        original_duration = float(json.loads(result.stdout)["format"]["duration"])
    else:
        # Estimate from edit notes
        all_timestamps = []
        for c in notes.get("cuts", []):
            all_timestamps.extend([c["start"], c["end"]])
        for s in notes.get("speedups", []):
            all_timestamps.extend([s["start"], s["end"]])
        for a in notes.get("anchor_moments", []):
            all_timestamps.extend([a["start"], a["end"]])
        if all_timestamps:
            original_duration = max(all_timestamps)

    # Display overview
    print_header("EDIT PLAN OVERVIEW")
    print_overview(notes, original_duration)

    # Anchor moments
    print_header("ANCHOR MOMENTS (Protected)")
    print_anchor_moments(notes)

    # Cuts
    print_header("CUTS")
    print_cuts(notes)

    # Speedups
    print_header("SPEEDUP SEGMENTS")
    print_speedups(notes)

    # B-roll flags
    print_header("B-ROLL FLAGS")
    print_broll_flags(notes)

    # Short candidate
    sc = notes.get("short_candidate", {})
    if sc and sc.get("start") is not None:
        print_header("SHORT CANDIDATE")
        dur = sc.get("end", 0) - sc.get("start", 0)
        print(f"  {fmt_time(sc['start'])} - {fmt_time(sc['end'])} ({dur:.1f}s)")
        print(f"  Reason: {sc.get('reason', 'N/A')}")

    # Interactive review
    if not args.no_interact:
        overrides = interactive_review(notes)

        if overrides["skip_cuts"] or overrides["override_cuts"]:
            overrides_path = "overrides.json"
            with open(overrides_path, "w") as f:
                json.dump(overrides, f, indent=2)
            log.info(f"Overrides saved to {overrides_path}")

            # Auto-run apply_edits if input video was provided
            if args.input and os.path.isfile(args.input):
                print(f"\n{BOLD}Running apply_edits.py with overrides...{RESET}")
                cmd = [
                    sys.executable, "apply_edits.py",
                    "--input", args.input,
                    "--edit-notes", args.edit_notes,
                    "--overrides", overrides_path,
                ]
                subprocess.run(cmd)
            else:
                print(f"\nTo apply edits with overrides, run:")
                print(f"  python apply_edits.py --input <video> "
                      f"--overrides {overrides_path}")
        else:
            log.info("No overrides — all cuts approved.")
            if args.input and os.path.isfile(args.input):
                print(f"\n{BOLD}Running apply_edits.py...{RESET}")
                cmd = [
                    sys.executable, "apply_edits.py",
                    "--input", args.input,
                    "--edit-notes", args.edit_notes,
                ]
                subprocess.run(cmd)
            else:
                print(f"\nTo apply edits, run:")
                print(f"  python apply_edits.py --input <video>")


if __name__ == "__main__":
    main()
