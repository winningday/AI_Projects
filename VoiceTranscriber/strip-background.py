#!/usr/bin/env python3
"""
Remove the background from an icon to create a transparent logo PNG.

Detects the background color from corners, then replaces all matching
pixels with transparency. Uses edge feathering for clean anti-aliased edges.

Usage: python3 strip-background.py <input.png> <output.png> [threshold]
  threshold: color difference tolerance for background detection (default: 40)
"""

import sys

def main():
    try:
        from PIL import Image
    except ImportError:
        print("Error: Pillow not installed. Run: pip3 install Pillow", file=sys.stderr)
        sys.exit(1)

    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.png> <output.png> [threshold]", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]
    threshold = int(sys.argv[3]) if len(sys.argv) > 3 else 40

    img = Image.open(input_path).convert("RGBA")
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

    # Process pixels: replace background with transparency
    # Use smooth alpha falloff for anti-aliased edges
    pixels = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            diff = abs(r - bg_r) + abs(g - bg_g) + abs(b - bg_b)

            if diff <= threshold:
                # Fully transparent
                pixels[x, y] = (r, g, b, 0)
            elif diff <= threshold * 2:
                # Feathered edge: partial transparency for smooth anti-aliasing
                alpha_ratio = (diff - threshold) / threshold
                new_alpha = int(a * alpha_ratio)
                pixels[x, y] = (r, g, b, new_alpha)
            # else: keep original pixel

    # Crop to content bounds (trim transparent edges)
    bbox = img.getbbox()
    if bbox:
        content = img.crop(bbox)
        content_w, content_h = content.size

        # Create square canvas (largest dimension)
        size = max(content_w, content_h)
        # Add a small margin (5%)
        canvas_size = int(size * 1.1)
        result = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

        # Center the content
        paste_x = (canvas_size - content_w) // 2
        paste_y = (canvas_size - content_h) // 2
        result.paste(content, (paste_x, paste_y), content)

        result.save(output_path)
        print(f"Transparent logo: {canvas_size}x{canvas_size} (from {w}x{h})", file=sys.stderr)
    else:
        print("Warning: No content detected after background removal", file=sys.stderr)
        img.save(output_path)


if __name__ == "__main__":
    main()
