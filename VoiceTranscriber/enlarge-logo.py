#!/usr/bin/env python3
"""
Enlarge the logo content within an icon image.

AI image generators often create logos with excessive padding.
This script detects the actual artwork, crops it, scales it up
to fill a target percentage of the canvas, and pastes it back
centered on the original background.

Usage: python3 enlarge-logo.py <input.png> <output.png> [fill_percent]
  fill_percent: how much of the canvas the logo should fill (default: 80)
"""

import sys
import os

def main():
    try:
        from PIL import Image, ImageFilter
    except ImportError:
        print("Error: Pillow not installed. Run: pip3 install Pillow", file=sys.stderr)
        sys.exit(1)

    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.png> <output.png> [fill_percent]", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]
    fill_pct = int(sys.argv[3]) if len(sys.argv) > 3 else 80

    img = Image.open(input_path).convert("RGBA")
    w, h = img.size

    # Sample background color from corners (average of 4 corners, 10x10 regions)
    corner_size = min(10, w // 10, h // 10)
    corners = [
        img.crop((0, 0, corner_size, corner_size)),
        img.crop((w - corner_size, 0, w, corner_size)),
        img.crop((0, h - corner_size, corner_size, h)),
        img.crop((w - corner_size, h - corner_size, w, h)),
    ]

    def avg_color(region):
        pixels = list(region.getdata())
        r = sum(p[0] for p in pixels) // len(pixels)
        g = sum(p[1] for p in pixels) // len(pixels)
        b = sum(p[2] for p in pixels) // len(pixels)
        a = sum(p[3] for p in pixels) // len(pixels)
        return (r, g, b, a)

    bg_samples = [avg_color(c) for c in corners]
    bg_r = sum(c[0] for c in bg_samples) // 4
    bg_g = sum(c[1] for c in bg_samples) // 4
    bg_b = sum(c[2] for c in bg_samples) // 4
    bg_a = sum(c[3] for c in bg_samples) // 4
    bg_color = (bg_r, bg_g, bg_b, bg_a)

    # Find bounding box of non-background pixels
    # A pixel is "content" if it differs from background by more than threshold
    threshold = 30
    pixels = img.load()
    min_x, min_y = w, h
    max_x, max_y = 0, 0
    found = False

    for y in range(h):
        for x in range(w):
            px = pixels[x, y]
            diff = abs(px[0] - bg_r) + abs(px[1] - bg_g) + abs(px[2] - bg_b)
            if diff > threshold:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
                found = True

    if not found:
        print("Warning: Could not detect logo content, copying as-is", file=sys.stderr)
        img.save(output_path)
        return

    # Add a small margin to the crop (2% of canvas)
    margin = int(w * 0.02)
    min_x = max(0, min_x - margin)
    min_y = max(0, min_y - margin)
    max_x = min(w - 1, max_x + margin)
    max_y = min(h - 1, max_y + margin)

    content_w = max_x - min_x + 1
    content_h = max_y - min_y + 1

    # Check if logo already fills enough space
    current_fill = max(content_w / w, content_h / h) * 100
    if current_fill >= fill_pct - 5:
        print(f"Logo already fills {current_fill:.0f}% of canvas, no enlargement needed", file=sys.stderr)
        img.save(output_path)
        return

    print(f"Logo content: {content_w}x{content_h} in {w}x{h} canvas ({current_fill:.0f}% fill)", file=sys.stderr)

    # Crop the content
    content = img.crop((min_x, min_y, max_x + 1, max_y + 1))

    # Calculate scale to fill target percentage
    target_size = int(w * fill_pct / 100)
    scale = target_size / max(content_w, content_h)

    new_w = int(content_w * scale)
    new_h = int(content_h * scale)

    # Scale up with high-quality resampling
    content_scaled = content.resize((new_w, new_h), Image.LANCZOS)

    # Create new canvas with background color
    result = Image.new("RGBA", (w, h), bg_color)

    # Paste centered
    paste_x = (w - new_w) // 2
    paste_y = (h - new_h) // 2
    result.paste(content_scaled, (paste_x, paste_y), content_scaled)

    result.save(output_path)
    print(f"Enlarged logo to {fill_pct}% fill ({new_w}x{new_h} in {w}x{h})", file=sys.stderr)


if __name__ == "__main__":
    main()
