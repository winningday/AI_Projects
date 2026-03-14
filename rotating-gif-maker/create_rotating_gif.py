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
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


# ---------------------------------------------------------------------------
# Auto face extraction — detect face, smart-crop, remove background
# ---------------------------------------------------------------------------

def detect_face(img: Image.Image):
    """
    Returns (x, y, w, h) of the largest detected face, or None.
    Uses OpenCV Haar cascade — no GPU, no model downloads.
    """
    try:
        import cv2
        import numpy as np
    except ImportError:
        print("  [warn] opencv-python not installed — skipping face detection.")
        return None

    arr = np.array(img.convert("RGB"))
    gray = cv2.cvtColor(arr, cv2.COLOR_RGB2GRAY)
    cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    )
    faces = cascade.detectMultiScale(
        gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60)
    )
    if len(faces) == 0:
        return None
    # Return the largest face by area
    return max(faces, key=lambda f: f[2] * f[3])


def extract_face(img: Image.Image) -> Image.Image | None:
    """
    Auto-detects a face, smart-crops to it, then runs rembg with the
    portrait-optimised isnet-general-use model to remove the background
    and any stray hands/arms. Returns an RGBA image or None if no face found.
    """
    face = detect_face(img)
    if face is None:
        return None

    fx, fy, fw, fh = face
    w, h = img.size
    print(f"  Face detected at ({fx},{fy}) size {fw}×{fh}")

    # Face center with a small upward nudge so hair gets slightly more
    # room than chin/neck (typical headshot framing).
    cx = fx + fw // 2
    cy = fy + fh // 2 - int(fh * 0.05)

    # half = 95% of face height → 40% breathing room on every side of the face.
    # This is the radius of the final square; the circle will fill it perfectly.
    half = int(fh * 0.95)

    # Clamp to image bounds for rembg (rembg wants real pixels, not padding).
    x1 = max(0, cx - half)
    y1 = max(0, cy - half)
    x2 = min(w, cx + half)
    y2 = min(h, cy + half)
    crop = img.crop((x1, y1, x2, y2))

    # rembg with isnet-general-use — best accuracy for portraits with occlusion
    try:
        from rembg import remove, new_session
        print("  Removing background (isnet-general-use)…")
        session = new_session("isnet-general-use")
        rgba = remove(crop, session=session)
    except ImportError:
        print("  [warn] rembg not installed — returning cropped image without bg removal.")
        rgba = crop.convert("RGBA")

    # ---- Expand to exact square centered on face -------------------------
    canvas_size = half * 2
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    paste_x = half - (cx - x1)
    paste_y = half - (cy - y1)
    canvas.paste(rgba, (paste_x, paste_y))

    # ---- Gradient fade to remove artifacts outside the face region -------
    # Face bbox in canvas coordinates
    face_top    = (fy - y1) + paste_y
    face_bottom = (fy + fh - y1) + paste_y

    # Fade zone above: full opacity at (face_top - 5%fh), transparent at (face_top - 40%fh)
    # Removes fingers / arms sitting above the hair.
    fade_top_opaque = face_top - int(fh * 0.05)
    fade_top_clear  = face_top - int(fh * 0.40)

    # Fade zone below: full opacity at (face_bottom + 8%fh), transparent at (face_bottom + 25%fh)
    # Removes the hard diagonal edge where the image boundary cuts through the neck.
    fade_bot_opaque = face_bottom + int(fh * 0.08)
    fade_bot_clear  = face_bottom + int(fh * 0.25)

    import numpy as np
    arr = np.array(canvas, dtype=np.float32)
    h_c = arr.shape[0]
    mult = np.ones(h_c, dtype=np.float32)

    # Top fade
    t0, t1 = max(0, fade_top_clear), max(0, fade_top_opaque)
    if t1 > t0:
        mult[:t0] = 0.0
        mult[t0:t1] = np.linspace(0.0, 1.0, t1 - t0)

    # Bottom fade
    b0 = min(h_c, fade_bot_opaque)
    b1 = min(h_c, fade_bot_clear)
    if b1 > b0:
        mult[b0:b1] = np.linspace(1.0, 0.0, b1 - b0)
        mult[b1:] = 0.0

    arr[:, :, 3] *= mult[:, np.newaxis]
    return Image.fromarray(arr.astype(np.uint8))


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

def apply_circular_mask(img: Image.Image, feather: int = 2) -> Image.Image:
    """Crop image to a circle with a softly feathered edge.
    Multiplies the existing alpha (from rembg / gradient fade) with the
    circle mask so prior transparency is preserved, not overwritten."""
    import numpy as np
    img = img.convert("RGBA")
    size = min(img.size)
    img = img.crop(((img.width - size) // 2,
                    (img.height - size) // 2,
                    (img.width + size) // 2,
                    (img.height + size) // 2))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    if feather > 0:
        mask = mask.filter(ImageFilter.GaussianBlur(feather))
    # Multiply existing alpha by circle mask instead of replacing it
    existing = np.array(img.split()[3], dtype=np.float32)
    circle   = np.array(mask, dtype=np.float32)
    combined = (existing * circle / 255.0).clip(0, 255).astype(np.uint8)
    img.putalpha(Image.fromarray(combined))
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

def _build_global_palette(frames_rgba: list, n_colors: int) -> Image.Image:
    """
    Sample every frame and derive a single shared palette.
    A global palette lets LZW compress far more efficiently across frames.
    """
    # Tile a subset of frames side-by-side so quantize sees all colours at once
    step = max(1, len(frames_rgba) // 8)          # sample up to 8 frames
    samples = [f.convert("RGB") for f in frames_rgba[::step]]
    w, h = samples[0].size
    combined = Image.new("RGB", (w * len(samples), h))
    for i, s in enumerate(samples):
        combined.paste(s, (i * w, 0))
    # Reserve one slot for the transparency colour
    return combined.quantize(colors=n_colors - 1, dither=0)


def _apply_palette(frame_rgba: Image.Image,
                   palette_img: Image.Image,
                   trans_index: int) -> Image.Image:
    """Map an RGBA frame onto the global palette; transparent pixels → trans_index."""
    r, g, b, a = frame_rgba.split()
    rgb = Image.merge("RGB", (r, g, b))

    # No dithering: solid colour runs → much better LZW compression
    p = rgb.quantize(palette=palette_img, dither=0)

    p_pixels = bytearray(p.tobytes())
    a_pixels = a.tobytes()
    for i, av in enumerate(a_pixels):
        if av < 128:
            p_pixels[i] = trans_index

    result = Image.new("P", frame_rgba.size)
    result.frombytes(bytes(p_pixels))

    pal = list(p.getpalette())
    while len(pal) < (trans_index + 1) * 3:
        pal.extend([0, 0, 0])
    pal[trans_index * 3: trans_index * 3 + 3] = [0, 0, 0]
    result.putpalette(pal)
    return result


def build_gif(
    frames_rgba: list,
    output_path: Path,
    fps: int,
    loop: int,
    n_colors: int = 32,
    lossy: int = 30,
) -> None:
    frame_duration_ms = max(20, round(1000 / fps))
    trans_index = n_colors - 1

    print("  Building global palette…")
    palette_img = _build_global_palette(frames_rgba, n_colors)

    print("  Quantizing frames…")
    palette_frames = [_apply_palette(f, palette_img, trans_index)
                      for f in frames_rgba]

    palette_frames[0].save(
        output_path,
        format="GIF",
        save_all=True,
        append_images=palette_frames[1:],
        duration=frame_duration_ms,
        loop=loop,
        optimize=True,
        transparency=trans_index,
        disposal=2,
    )

    # Post-process with gifsicle if available — typically saves 40-70 % more
    gifsicle = _find_gifsicle()
    if gifsicle:
        print(f"  Running gifsicle --optimize=3 --lossy={lossy}…")
        tmp = output_path.with_suffix(".tmp.gif")
        output_path.rename(tmp)
        result = subprocess.run(
            [gifsicle, "--optimize=3", f"--lossy={lossy}",
             "-o", str(output_path), str(tmp)],
            capture_output=True,
        )
        tmp.unlink(missing_ok=True)
        if result.returncode != 0:
            # Fallback: just keep the unoptimized version
            output_path.rename(tmp)
            tmp.rename(output_path)
    else:
        print("  [tip] Install gifsicle for an extra 40-70% size reduction.")


def _find_gifsicle() -> str | None:
    import shutil
    return shutil.which("gifsicle")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create a rotating GIF from an image."
    )
    parser.add_argument("--input",  "-i", required=True,  help="Input image path")
    parser.add_argument("--output", "-o", default=None,   help="Output GIF path (default: <input>_rotating.gif)")

    # Face extraction
    parser.add_argument("--face", action="store_true",
                        help="Auto-detect and extract face (smart crop + bg removal)")
    parser.add_argument("--auto", action="store_true", default=True,
                        help="Auto-detect face and use face pipeline if found (default: on)")
    parser.add_argument("--no-auto", dest="auto", action="store_false",
                        help="Disable auto face detection")

    # Crop / size
    parser.add_argument("--crop",   nargs=2, type=int, metavar=("W", "H"),
                        help="Crop a W×H region from the centre of the image")
    parser.add_argument("--interactive-crop", action="store_true",
                        help="Interactively enter a crop region")
    parser.add_argument("--size",   type=int, default=120,
                        help="Final canvas size in pixels (square). Default: 120")
    parser.add_argument("--circle", action="store_true",
                        help="Apply a circular mask to the image")

    # Background
    parser.add_argument("--remove-bg", action="store_true",
                        help="Remove image background (requires rembg)")
    parser.add_argument("--bg-white", action="store_true",
                        help="Use a solid white background instead of transparent")

    # Animation
    parser.add_argument("--fps",      type=int,   default=12,
                        help="Frames per second. Default: 12")
    parser.add_argument("--duration", type=float, default=2.0,
                        help="Duration of one full rotation in seconds. Default: 2.0")
    parser.add_argument("--direction", choices=["cw", "ccw"], default="cw",
                        help="Rotation direction: cw (clockwise) or ccw. Default: cw")
    parser.add_argument("--loop",     type=int,   default=0,
                        help="Number of loops (0 = infinite). Default: 0")
    parser.add_argument("--colors",   type=int,   default=128,
                        help="Palette size (2-256). Fewer = smaller file. Default: 128")
    parser.add_argument("--lossy",    type=int,   default=10,
                        help="gifsicle lossy level (0=lossless, 80=aggressive). Default: 10")

    args = parser.parse_args()

    # ---- Load image --------------------------------------------------------
    input_path = Path(args.input)
    if not input_path.exists():
        sys.exit(f"Error: file not found: {input_path}")

    output_path = Path(args.output) if args.output else \
                  input_path.with_stem(input_path.stem + "_rotating").with_suffix(".gif")

    print(f"Loading: {input_path}")
    img = Image.open(input_path).convert("RGBA")

    # ---- Face extraction (auto or explicit) --------------------------------
    use_face_pipeline = args.face
    if not use_face_pipeline and args.auto:
        print("  Auto-detecting face…")
        face = detect_face(img)
        if face is not None:
            print("  Face found — using face extraction pipeline.")
            use_face_pipeline = True
        else:
            print("  No face detected — using standard pipeline.")

    if use_face_pipeline:
        extracted = extract_face(img)
        if extracted is not None:
            img = extracted
            # Always apply circular mask for face output
            print("  Applying circular mask…")
            img = apply_circular_mask(img)
        else:
            print("  [warn] Face extraction failed — falling back to standard pipeline.")
    else:
        # ---- Standard pipeline ---------------------------------------------
        if args.remove_bg:
            img = remove_background(img)

        if args.crop:
            print(f"  Cropping to centre {args.crop[0]}×{args.crop[1]}…")
            img = crop_center(img, args.crop[0], args.crop[1])
        elif args.interactive_crop:
            img = crop_interactive(img)

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
    build_gif(frames, output_path, fps=args.fps, loop=args.loop,
              n_colors=n_colors, lossy=args.lossy)

    size_kb = output_path.stat().st_size / 1024
    print(f"\nDone! {output_path}  ({size_kb:.1f} KB, {total_frames} frames)")


if __name__ == "__main__":
    main()
