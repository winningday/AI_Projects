#!/bin/bash
# ============================================================================
# make-icon.sh — Reusable macOS App Icon Generator
# ============================================================================
# Generates a properly formatted .icns file from any 1024x1024 PNG source.
#
# Usage:
#   ./make-icon.sh <source.png> [output.icns]
#
# Requirements:
#   - macOS with sips and iconutil (both built-in)
#   - Source image should be 1024x1024 PNG, FULL SQUARE (no rounded corners!)
#
# Icon Design Rules:
#   1. Design a FULL SQUARE — macOS applies its own squircle mask
#   2. Keep the logo within the center 80% (safe zone) to avoid clipping
#   3. Use opaque background — no transparency at the edges
#   4. Export as 32-bit PNG, 1024x1024, sRGB or Display P3
#   5. Never bake in rounded corners yourself
#
# If your source image has rounded corners or transparency issues, this script
# can optionally generate a full-bleed version by sampling the background color
# and filling behind it. Use --fix-corners flag.
# ============================================================================

set -euo pipefail

# --- Argument parsing -------------------------------------------------------
FIX_CORNERS=false
PADDING=0
POSITIONAL_ARGS=()

usage() {
    echo "Usage: $0 [options] <source.png> [output.icns]"
    echo ""
    echo "Options:"
    echo "  --fix-corners     Fix source images with baked-in rounded corners"
    echo "                    by sampling the background color and filling behind"
    echo "  --padding <px>    Add padding around the logo (shrinks logo by this"
    echo "                    many pixels on each side). Useful for ensuring the"
    echo "                    safe zone. Default: 0"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 icon.png                         # Basic conversion"
    echo "  $0 icon.png MyApp.icns              # Custom output name"
    echo "  $0 --fix-corners old-logo.png       # Fix rounded corner artifacts"
    echo "  $0 --padding 100 logo.png           # Add 100px safe zone padding"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix-corners)
            FIX_CORNERS=true
            shift
            ;;
        --padding)
            PADDING="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

set -- "${POSITIONAL_ARGS[@]}"

if [ $# -lt 1 ]; then
    echo "Error: No source image specified."
    echo ""
    usage
fi

SOURCE_ICON="$1"
OUTPUT_ICNS="${2:-$(dirname "$SOURCE_ICON")/AppIcon.icns}"

if [ ! -f "${SOURCE_ICON}" ]; then
    echo "Error: Source image not found: ${SOURCE_ICON}"
    exit 1
fi

# --- Validate source image ---------------------------------------------------
echo "==> Validating source image: ${SOURCE_ICON}"

# Check dimensions using sips
DIMENSIONS=$(sips -g pixelWidth -g pixelHeight "${SOURCE_ICON}" 2>/dev/null)
WIDTH=$(echo "$DIMENSIONS" | grep pixelWidth | awk '{print $2}')
HEIGHT=$(echo "$DIMENSIONS" | grep pixelHeight | awk '{print $2}')

if [ "$WIDTH" != "1024" ] || [ "$HEIGHT" != "1024" ]; then
    echo "Warning: Source image is ${WIDTH}x${HEIGHT}, expected 1024x1024."
    echo "         The image will be resized to 1024x1024."
fi

# --- Create temporary workspace ----------------------------------------------
WORK_DIR=$(mktemp -d)
ICONSET_DIR="${WORK_DIR}/AppIcon.iconset"
mkdir -p "${ICONSET_DIR}"
trap "rm -rf '${WORK_DIR}'" EXIT

# --- Prepare source image ----------------------------------------------------
PREPARED="${WORK_DIR}/prepared.png"

# Resize to 1024x1024 if needed
sips -z 1024 1024 "${SOURCE_ICON}" --out "${PREPARED}" >/dev/null 2>&1

# Fix rounded corners if requested
if [ "$FIX_CORNERS" = true ]; then
    echo "==> Fixing rounded corners (full-bleed fill)..."
    FULLBLEED="${WORK_DIR}/fullbleed.png"

    swift - "${PREPARED}" "${FULLBLEED}" << 'SWIFT_FULLBLEED'
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else { exit(1) }

guard let srcImage = NSImage(contentsOfFile: args[1]) else {
    fputs("Error: cannot load source icon\n", stderr)
    exit(1)
}

let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!

let rect = NSRect(x: 0, y: 0, width: size, height: size)

// Sample background color from center-top area (safely inside any rounded region)
let sampleRep = NSBitmapImageRep(data: srcImage.tiffRepresentation!)!
let sx = sampleRep.pixelsWide / 2
let sy = Int(Double(sampleRep.pixelsHigh) * 0.9)
let bgColor = sampleRep.colorAt(x: sx, y: sy)
    ?? NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0)

// Fill entire canvas with sampled background color
bgColor.setFill()
rect.fill()

// Draw original icon on top — transparent corners blend seamlessly
srcImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Error: cannot create PNG\n", stderr)
    exit(1)
}
try! pngData.write(to: URL(fileURLWithPath: args[2]))
SWIFT_FULLBLEED

    if [ -f "${FULLBLEED}" ]; then
        cp "${FULLBLEED}" "${PREPARED}"
        echo "    Rounded corners fixed."
    else
        echo "    Warning: full-bleed fix failed, using original image."
    fi
fi

# Add padding if requested
if [ "$PADDING" -gt 0 ]; then
    echo "==> Adding ${PADDING}px padding (safe zone)..."
    PADDED="${WORK_DIR}/padded.png"

    swift - "${PREPARED}" "${PADDED}" "${PADDING}" << 'SWIFT_PADDING'
import AppKit

let args = CommandLine.arguments
guard args.count >= 4, let padding = Int(args[3]) else { exit(1) }

guard let srcImage = NSImage(contentsOfFile: args[1]) else {
    fputs("Error: cannot load source icon\n", stderr)
    exit(1)
}

let size: CGFloat = 1024
let p = CGFloat(padding)
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!

let canvas = NSRect(x: 0, y: 0, width: size, height: size)

// Sample background color from center of image
let sampleRep = NSBitmapImageRep(data: srcImage.tiffRepresentation!)!
let bgColor = sampleRep.colorAt(x: sampleRep.pixelsWide / 2, y: Int(Double(sampleRep.pixelsHigh) * 0.9))
    ?? NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0)

// Fill background
bgColor.setFill()
canvas.fill()

// Draw the logo smaller (with padding)
let logoRect = NSRect(x: p, y: p, width: size - 2 * p, height: size - 2 * p)
srcImage.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Error: cannot create PNG\n", stderr)
    exit(1)
}
try! pngData.write(to: URL(fileURLWithPath: args[2]))
SWIFT_PADDING

    if [ -f "${PADDED}" ]; then
        cp "${PADDED}" "${PREPARED}"
        echo "    Padding added."
    else
        echo "    Warning: padding step failed, using unpadded image."
    fi
fi

# --- Generate all required iconset sizes -------------------------------------
echo "==> Generating iconset sizes..."

for size in 16 32 64 128 256 512 1024; do
    sips -z "${size}" "${size}" "${PREPARED}" --out "${WORK_DIR}/_s${size}.png" >/dev/null 2>&1
done

# Apple's required naming convention
cp "${WORK_DIR}/_s16.png"   "${ICONSET_DIR}/icon_16x16.png"
cp "${WORK_DIR}/_s32.png"   "${ICONSET_DIR}/icon_16x16@2x.png"
cp "${WORK_DIR}/_s32.png"   "${ICONSET_DIR}/icon_32x32.png"
cp "${WORK_DIR}/_s64.png"   "${ICONSET_DIR}/icon_32x32@2x.png"
cp "${WORK_DIR}/_s128.png"  "${ICONSET_DIR}/icon_128x128.png"
cp "${WORK_DIR}/_s256.png"  "${ICONSET_DIR}/icon_128x128@2x.png"
cp "${WORK_DIR}/_s256.png"  "${ICONSET_DIR}/icon_256x256.png"
cp "${WORK_DIR}/_s512.png"  "${ICONSET_DIR}/icon_256x256@2x.png"
cp "${WORK_DIR}/_s512.png"  "${ICONSET_DIR}/icon_512x512.png"
cp "${WORK_DIR}/_s1024.png" "${ICONSET_DIR}/icon_512x512@2x.png"

# --- Convert to .icns --------------------------------------------------------
echo "==> Converting to .icns..."

if iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICNS}" 2>/dev/null; then
    echo "==> Icon generated successfully: ${OUTPUT_ICNS}"
    echo ""
    echo "    File: ${OUTPUT_ICNS}"
    echo "    Size: $(du -h "${OUTPUT_ICNS}" | cut -f1)"
    echo ""
    echo "    To use in your app, set CFBundleIconFile to 'AppIcon' in Info.plist"
    echo "    and place the .icns file in Contents/Resources/"
else
    echo "Error: iconutil failed to create .icns file."
    echo "       Make sure you're running on macOS."
    exit 1
fi
