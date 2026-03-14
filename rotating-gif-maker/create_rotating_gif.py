#!/usr/bin/env python3
"""
Rotating GIF Maker
------------------
Takes an image, optionally removes the background, crops/resizes it,
and produces an animated rotating GIF — great for email signatures and logos.

Usage:
    python create_rotating_gif.py --input photo.jpg --output logo_spin.gif
    python create_rotating_gif.py --input photo.jpg --crop 400 400 --size 200 --fps 30 --duration 2
    python create_rotating_gif.py --input photo.jpg --remove-bg --size 150 --output spin.gif
"""

import argparse
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


# ---------------------------------------------------------------------------
# Background removal (requires `rembg`; graceful fallback if not installed)
# ---------------------------------------------------------------------------

def remove_background(img: Image.Image) -> Image.Image:
    try:
        from rembg import remove
        print("  Removing background with rembg…")
        return remove(img)
    except ImportError:
        print("  [warn] rembg not installed — skipping background removal.")
        print("         Run: pip install rembg  to enable this feature.")
        return img


# ---------------------------------------------------------------------------
# Crop helpers
# ---------------------------------------------------------------------------

def crop_center(img: Image.Image, crop_w: int, crop_h: int) -> Image.Image:
    """Crop a centered rectangle from the image."""
    w, h = img.size
    left = max((w - crop_w) // 2, 0)
    top  = max((h - crop_h) // 2, 0)
    right  = left + min(crop_w, w)
    bottom = top  + min(crop_h, h)
    return img.crop((left, top, right, bottom))


def crop_interactive(img: Image.Image) -> Image.Image:
    """Ask the user to specify a crop region via the terminal."""
    w, h = img.size
    print(f"\n  Image size: {w} x {h} px")
    print("  Enter crop region (leave blank to skip cropping):")
    try:
        left   = int(input(f"    left   [0]    : ") or 0)
        top    = int(input(f"    top    [0]    : ") or 0)
        right  = int(input(f"    right  [{w}] : ") or w)
        bottom = int(input(f"    bottom [{h}] : ") or h)
        return img.crop((left, top, right, bottom))
    except (ValueError, EOFError):
        print("  Invalid input — skipping crop.")
        return img


# ---------------------------------------------------------------------------
# Round / circular mask (optional)
# ---------------------------------------------------------------------------

def apply_circular_mask(img: Image.Image) -> Image.Image:
    """Crop image to a circle (keeps transparency)."""
    img = img.convert("RGBA")
    size = min(img.size)
    img = img.crop(((img.width - size) // 2,
                    (img.height - size) // 2,
                    (img.width + size) // 2,
                    (img.height + size) // 2))
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, size - 1, size - 1), fill=255)
    img.putalpha(mask)
    return img


# ---------------------------------------------------------------------------
# Frame generation
# ---------------------------------------------------------------------------

def make_frame(
    img: Image.Image,
    angle: float,
    canvas_size: int,
    bg_color: tuple,
) -> Image.Image:
    """
    Rotate *img* by *angle* degrees and paste it onto a square canvas.

    bg_color = (R, G, B, 0) gives a transparent canvas (for GIFs the
    palette will approximate transparency via a matte colour).
    """
    rotated = img.rotate(angle, resample=Image.BICUBIC, expand=False)
    canvas = Image.new("RGBA", (canvas_size, canvas_size), bg_color)
    # Centre the rotated image
    x = (canvas_size - rotated.width)  // 2
    y = (canvas_size - rotated.height) // 2
    canvas.paste(rotated, (x, y), rotated if rotated.mode == "RGBA" else None)
    return canvas


# ---------------------------------------------------------------------------
# GIF assembly
# ---------------------------------------------------------------------------

def _rgba_to_p(frame_rgba: Image.Image, n_colors: int) -> tuple:
    """
    Convert an RGBA frame to P-mode (palette) while preserving transparency.
    Returns (p_frame, transparency_index).
    """
    r, g, b, a = frame_rgba.split()
    rgb = Image.merge("RGB", (r, g, b))

    # Reserve the last palette slot for the transparent colour
    trans_index = n_colors - 1
    p = rgb.quantize(colors=trans_index, dither=Image.Dither.FLOYDSTEINBERG)

    # Replace fully-transparent pixels with the reserved index
    p_pixels = list(p.tobytes())
    a_pixels = list(a.tobytes())
    new_pixels = [trans_index if av < 128 else p_pixels[i]
                  for i, av in enumerate(a_pixels)]

    result = Image.new("P", frame_rgba.size)
    result.putdata(new_pixels)

    palette = list(p.getpalette())
    # Ensure palette is long enough and zero out the transparency slot
    while len(palette) < (n_colors) * 3:
        palette.extend([0, 0, 0])
    palette[trans_index * 3: trans_index * 3 + 3] = [0, 0, 0]
    result.putpalette(palette)

    return result, trans_index


def build_gif(
    frames_rgba: list,
    output_path: Path,
    fps: int,
    loop: int,
    n_colors: int = 64,
) -> None:
    frame_duration_ms = max(20, round(1000 / fps))

    palette_frames = []
    trans_index = None
    for frame in frames_rgba:
        p_frame, trans_index = _rgba_to_p(frame, n_colors)
        palette_frames.append(p_frame)

    palette_frames[0].save(
        output_path,
        format="GIF",
        save_all=True,
        append_images=palette_frames[1:],
        duration=frame_duration_ms,
        loop=loop,
        optimize=True,
        transparency=trans_index,
        disposal=2,          # clear to background between frames
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create a rotating GIF from an image."
    )
    parser.add_argument("--input",  "-i", required=True,  help="Input image path")
    parser.add_argument("--output", "-o", default=None,   help="Output GIF path (default: <input>_rotating.gif)")

    # Crop / size
    parser.add_argument("--crop",   nargs=2, type=int, metavar=("W", "H"),
                        help="Crop a W×H region from the centre of the image")
    parser.add_argument("--interactive-crop", action="store_true",
                        help="Interactively enter a crop region")
    parser.add_argument("--size",   type=int, default=200,
                        help="Final canvas size in pixels (square). Default: 200")
    parser.add_argument("--circle", action="store_true",
                        help="Apply a circular mask to the image")

    # Background
    parser.add_argument("--remove-bg", action="store_true",
                        help="Remove image background (requires rembg)")
    parser.add_argument("--bg-white", action="store_true",
                        help="Use a solid white background instead of transparent")

    # Animation
    parser.add_argument("--fps",      type=int,   default=24,
                        help="Frames per second. Default: 24")
    parser.add_argument("--duration", type=float, default=2.0,
                        help="Duration of one full rotation in seconds. Default: 2.0")
    parser.add_argument("--direction", choices=["cw", "ccw"], default="cw",
                        help="Rotation direction: cw (clockwise) or ccw. Default: cw")
    parser.add_argument("--loop",     type=int,   default=0,
                        help="Number of loops (0 = infinite). Default: 0")
    parser.add_argument("--colors",   type=int,   default=64,
                        help="Palette size (2-256). Fewer = smaller file. Default: 64")

    args = parser.parse_args()

    # ---- Load image --------------------------------------------------------
    input_path = Path(args.input)
    if not input_path.exists():
        sys.exit(f"Error: file not found: {input_path}")

    output_path = Path(args.output) if args.output else \
                  input_path.with_stem(input_path.stem + "_rotating").with_suffix(".gif")

    print(f"Loading: {input_path}")
    img = Image.open(input_path).convert("RGBA")

    # ---- Background removal ------------------------------------------------
    if args.remove_bg:
        img = remove_background(img)

    # ---- Crop --------------------------------------------------------------
    if args.crop:
        print(f"  Cropping to centre {args.crop[0]}×{args.crop[1]}…")
        img = crop_center(img, args.crop[0], args.crop[1])
    elif args.interactive_crop:
        img = crop_interactive(img)

    # ---- Circular mask -----------------------------------------------------
    if args.circle:
        print("  Applying circular mask…")
        img = apply_circular_mask(img)

    # ---- Resize to final canvas size ---------------------------------------
    size = args.size
    # Fit inside size×size while preserving aspect ratio
    img.thumbnail((size, size), Image.LANCZOS)
    print(f"  Image resized to: {img.size}")

    # ---- Background colour for canvas frames -------------------------------
    bg_color = (255, 255, 255, 255) if args.bg_white else (255, 255, 255, 0)

    # ---- Generate frames ---------------------------------------------------
    total_frames = max(2, round(args.fps * args.duration))
    print(f"  Generating {total_frames} frames at {args.fps} fps…")

    frames = []
    for i in range(total_frames):
        fraction = i / total_frames                        # 0.0 → 1.0
        angle = fraction * 360.0
        # PIL rotate() is counter-clockwise for positive angles;
        # negate for clockwise.
        if args.direction == "cw":
            angle = -angle
        frame = make_frame(img, angle, size, bg_color)
        frames.append(frame)

    # ---- Save GIF ----------------------------------------------------------
    print(f"  Saving GIF → {output_path}")
    n_colors = max(2, min(256, args.colors))
    build_gif(frames, output_path, fps=args.fps, loop=args.loop, n_colors=n_colors)

    size_kb = output_path.stat().st_size / 1024
    print(f"\nDone! {output_path}  ({size_kb:.1f} KB, {total_frames} frames)")


if __name__ == "__main__":
    main()
