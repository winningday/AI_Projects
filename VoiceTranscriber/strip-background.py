#!/usr/bin/env python3
"""
Remove the background from an icon to create transparent logo PNGs.

Detects the background color from corners, then replaces all matching
pixels with transparency. Uses edge feathering for clean anti-aliased edges.

Generates two variants:
  - Dark mode version (original artwork, for use on dark backgrounds)
  - Light mode version (darkened artwork, for use on light backgrounds)

Usage: python3 strip-background.py <input.png> <output_prefix> [threshold]
  Outputs: <output_prefix>-dark.png and <output_prefix>-light.png
  threshold: color difference tolerance for background detection (default: 40)

  For single-file output (legacy):
    python3 strip-background.py <input.png> <output.png> [threshold]
    (if output ends in .png, only produces the dark-mode version)
"""

import sys
import os


def strip_background(img, threshold=40):
    """Remove background and return transparent image."""
    from PIL import Image

    img = img.copy()
    w, h = img.size

    # Sample background from corners
    corner_size = min(10, w // 10, h // 10)
    corner_regions = [
        img.crop((0, 0, corner_size, corner_size)),
        img.crop((w - corner_size, 0, w, corner_size)),
        img.crop((0, h - corner_size, corner_size, h)),
        img.crop((w - corner_size, h - corner_size, w, h)),
    ]

    def avg_color(region):
        pixels = list(region.getdata())
        n = len(pixels)
        return (
            sum(p[0] for p in pixels) // n,
            sum(p[1] for p in pixels) // n,
            sum(p[2] for p in pixels) // n,
        )

    samples = [avg_color(c) for c in corner_regions]
    bg_r = sum(c[0] for c in samples) // 4
    bg_g = sum(c[1] for c in samples) // 4
    bg_b = sum(c[2] for c in samples) // 4

    print(f"Detected background: RGB({bg_r}, {bg_g}, {bg_b})", file=sys.stderr)

    # Replace background with transparency, feather edges
    pixels = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            diff = abs(r - bg_r) + abs(g - bg_g) + abs(b - bg_b)

            if diff <= threshold:
                pixels[x, y] = (r, g, b, 0)
            elif diff <= threshold * 2:
                alpha_ratio = (diff - threshold) / threshold
                new_alpha = int(a * alpha_ratio)
                pixels[x, y] = (r, g, b, new_alpha)

    return img


def crop_to_content(img, margin_pct=0.05):
    """Crop to content bounds and center on a square canvas."""
    from PIL import Image

    bbox = img.getbbox()
    if not bbox:
        return img

    content = img.crop(bbox)
    content_w, content_h = content.size

    size = max(content_w, content_h)
    canvas_size = int(size * (1 + margin_pct * 2))
    result = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    paste_x = (canvas_size - content_w) // 2
    paste_y = (canvas_size - content_h) // 2
    result.paste(content, (paste_x, paste_y), content)
    return result


def make_light_mode_variant(img):
    """Darken the artwork so it's visible on light backgrounds.

    Shifts light/metallic pixels toward darker tones while preserving
    the shape, gradients, and alpha channel.
    """
    from PIL import ImageEnhance

    img = img.copy()
    pixels = img.load()
    w, h = img.size

    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue

            # Darken: reduce brightness significantly
            # Map the luminance range so light metallic becomes dark metallic
            lum = (r * 299 + g * 587 + b * 114) // 1000

            # Invert-ish: light pixels become dark, dark pixels stay dark
            # This preserves gradient structure while making it visible on white
            factor = max(0.1, 1.0 - (lum / 255) * 0.85)
            new_r = int(r * factor)
            new_g = int(g * factor)
            new_b = int(b * factor)

            pixels[x, y] = (new_r, new_g, new_b, a)

    return img


def main():
    try:
        from PIL import Image
    except ImportError:
        print("Error: Pillow not installed. Run: pip3 install Pillow", file=sys.stderr)
        sys.exit(1)

    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.png> <output_prefix> [threshold]", file=sys.stderr)
        print(f"  Outputs: <output_prefix>-dark.png and <output_prefix>-light.png", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    output_arg = sys.argv[2]
    threshold = int(sys.argv[3]) if len(sys.argv) > 3 else 40

    img = Image.open(input_path).convert("RGBA")

    # Strip background
    transparent = strip_background(img, threshold)
    cropped = crop_to_content(transparent)

    # Determine output mode
    if output_arg.endswith(".png"):
        # Legacy single-file mode
        cropped.save(output_arg)
        w, h = cropped.size
        print(f"Transparent logo: {w}x{h} (from {img.size[0]}x{img.size[1]})", file=sys.stderr)
    else:
        # Dual-mode output
        dark_path = f"{output_arg}-dark.png"
        light_path = f"{output_arg}-light.png"

        # Dark mode: original artwork (light metallic on transparent)
        cropped.save(dark_path)
        print(f"Dark mode logo: {dark_path}", file=sys.stderr)

        # Light mode: darkened artwork (dark metallic on transparent)
        light_variant = make_light_mode_variant(cropped)
        light_variant.save(light_path)
        print(f"Light mode logo: {light_path}", file=sys.stderr)

        w, h = cropped.size
        print(f"Both variants: {w}x{h} (from {img.size[0]}x{img.size[1]})", file=sys.stderr)


if __name__ == "__main__":
    main()
