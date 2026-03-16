#!/usr/bin/env python3
"""
Enlarge the logo content within an icon image.

AI image generators often create logos with excessive padding.
This script detects the actual artwork, crops it, scales it up
to fill a target percentage of the canvas, and pastes it back
centered on the original background.

Usage:
  python3 enlarge-logo.py <input.png> <output.png> [fill_percent]
  python3 enlarge-logo.py --preview <input.png>

Options:
  --preview   Generate an HTML comparison showing the logo at 60%, 70%, 80%, 90%
              fill levels. Opens in browser so you can pick the right size.
  fill_percent: how much of the canvas the logo should fill (default: 80)
"""

import sys
import os
import base64
import tempfile
import subprocess
from io import BytesIO


def detect_content(img, bg_color, threshold=30):
    """Find the bounding box of non-background pixels."""
    w, h = img.size
    bg_r, bg_g, bg_b = bg_color[0], bg_color[1], bg_color[2]
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
        return None

    # Add a small margin (2% of canvas)
    margin = int(w * 0.02)
    min_x = max(0, min_x - margin)
    min_y = max(0, min_y - margin)
    max_x = min(w - 1, max_x + margin)
    max_y = min(h - 1, max_y + margin)

    return (min_x, min_y, max_x + 1, max_y + 1)


def get_bg_color(img):
    """Sample background color from corners."""
    w, h = img.size
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
    return (
        sum(c[0] for c in bg_samples) // 4,
        sum(c[1] for c in bg_samples) // 4,
        sum(c[2] for c in bg_samples) // 4,
        sum(c[3] for c in bg_samples) // 4,
    )


def enlarge(img, fill_pct, bg_color, bbox):
    """Enlarge logo content to fill target percentage of canvas."""
    from PIL import Image

    w, h = img.size
    content = img.crop(bbox)
    content_w = bbox[2] - bbox[0]
    content_h = bbox[3] - bbox[1]

    target_size = int(w * fill_pct / 100)
    scale = target_size / max(content_w, content_h)
    new_w = int(content_w * scale)
    new_h = int(content_h * scale)

    content_scaled = content.resize((new_w, new_h), Image.LANCZOS)

    result = Image.new("RGBA", (w, h), bg_color)
    paste_x = (w - new_w) // 2
    paste_y = (h - new_h) // 2
    result.paste(content_scaled, (paste_x, paste_y), content_scaled)
    return result


def img_to_data_uri(img):
    """Convert PIL Image to base64 data URI."""
    buf = BytesIO()
    img.save(buf, format="PNG")
    b64 = base64.b64encode(buf.getvalue()).decode()
    return f"data:image/png;base64,{b64}"


def preview(input_path):
    """Generate HTML comparison at multiple fill levels and open in browser."""
    from PIL import Image

    img = Image.open(input_path).convert("RGBA")
    bg_color = get_bg_color(img)
    bbox = detect_content(img, bg_color)

    if bbox is None:
        print("Error: Could not detect logo content", file=sys.stderr)
        sys.exit(1)

    w, h = img.size
    content_w = bbox[2] - bbox[0]
    content_h = bbox[3] - bbox[1]
    current_fill = max(content_w / w, content_h / h) * 100

    # Generate versions at different fill levels
    levels = [("Original", None)] + [(f"{p}%", p) for p in [60, 70, 75, 80, 85, 90]]
    cards = []

    for label, pct in levels:
        if pct is None:
            result = img
        else:
            result = enlarge(img, pct, bg_color, bbox)

        data_uri = img_to_data_uri(result)
        highlight = ' style="border: 3px solid #4CAF50; box-shadow: 0 0 15px rgba(76,175,80,0.5);"' if pct == 80 else ""
        rec = " (recommended)" if pct == 80 else ""
        cards.append(f"""
        <div class="card"{highlight}>
            <img src="{data_uri}" alt="{label}">
            <div class="label">{label}{rec}</div>
        </div>""")

    html = f"""<!DOCTYPE html>
<html>
<head>
<title>Logo Size Preview — Verbalize</title>
<style>
    body {{
        background: #1a1a1a;
        color: #fff;
        font-family: -apple-system, BlinkMacSystemFont, sans-serif;
        padding: 30px;
        margin: 0;
    }}
    h1 {{ text-align: center; font-weight: 300; margin-bottom: 5px; }}
    .info {{ text-align: center; color: #888; margin-bottom: 30px; font-size: 14px; }}
    .grid {{
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 24px;
        max-width: 1400px;
        margin: 0 auto;
    }}
    .card {{
        background: #2a2a2a;
        border-radius: 16px;
        padding: 16px;
        text-align: center;
        border: 2px solid #333;
        transition: transform 0.2s;
    }}
    .card:hover {{ transform: scale(1.03); }}
    .card img {{
        width: 100%;
        border-radius: 12px;
        aspect-ratio: 1;
        object-fit: contain;
    }}
    .label {{
        margin-top: 10px;
        font-size: 16px;
        font-weight: 600;
    }}
    .usage {{
        text-align: center;
        margin-top: 30px;
        color: #888;
        font-size: 13px;
    }}
    code {{ background: #333; padding: 2px 8px; border-radius: 4px; font-size: 13px; }}
</style>
</head>
<body>
    <h1>Logo Size Preview</h1>
    <div class="info">
        Current logo fills {current_fill:.0f}% of the {w}x{h} canvas
        &nbsp;|&nbsp; Content detected: {content_w}x{content_h}px
    </div>
    <div class="grid">
        {"".join(cards)}
    </div>
    <div class="usage">
        Pick a size, then run: <code>python3 enlarge-logo.py icon.png icon.png 80</code>
        (replace 80 with your chosen percentage)
    </div>
</body>
</html>"""

    preview_path = os.path.join(tempfile.gettempdir(), "verbalize-logo-preview.html")
    with open(preview_path, "w") as f:
        f.write(html)

    print(f"Preview saved to: {preview_path}", file=sys.stderr)

    # Try to open in browser
    try:
        subprocess.run(["open", preview_path], check=True)
        print("Opened in browser!", file=sys.stderr)
    except (FileNotFoundError, subprocess.CalledProcessError):
        print(f"Open {preview_path} in your browser to compare sizes", file=sys.stderr)


def main():
    try:
        from PIL import Image
    except ImportError:
        print("Error: Pillow not installed. Run: pip3 install Pillow", file=sys.stderr)
        sys.exit(1)

    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.png> <output.png> [fill_percent]", file=sys.stderr)
        print(f"       {sys.argv[0]} --preview <input.png>", file=sys.stderr)
        sys.exit(1)

    # Preview mode
    if sys.argv[1] == "--preview":
        if len(sys.argv) < 3:
            print("Usage: --preview <input.png>", file=sys.stderr)
            sys.exit(1)
        preview(sys.argv[2])
        return

    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.png> <output.png> [fill_percent]", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]
    fill_pct = int(sys.argv[3]) if len(sys.argv) > 3 else 80

    img = Image.open(input_path).convert("RGBA")
    w, h = img.size
    bg_color = get_bg_color(img)
    bbox = detect_content(img, bg_color)

    if bbox is None:
        print("Warning: Could not detect logo content, copying as-is", file=sys.stderr)
        img.save(output_path)
        return

    content_w = bbox[2] - bbox[0]
    content_h = bbox[3] - bbox[1]
    current_fill = max(content_w / w, content_h / h) * 100

    if current_fill >= fill_pct - 5:
        print(f"Logo already fills {current_fill:.0f}% of canvas, no enlargement needed", file=sys.stderr)
        img.save(output_path)
        return

    print(f"Logo content: {content_w}x{content_h} in {w}x{h} canvas ({current_fill:.0f}% fill)", file=sys.stderr)

    result = enlarge(img, fill_pct, bg_color, bbox)
    result.save(output_path)

    new_size = int(max(content_w, content_h) * (w * fill_pct / 100) / max(content_w, content_h))
    print(f"Enlarged logo to {fill_pct}% fill ({new_size}px in {w}x{h})", file=sys.stderr)


if __name__ == "__main__":
    main()
