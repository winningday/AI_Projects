#!/bin/bash
# Build Verbalize as a macOS .app bundle + optional DMG installer
# Usage: ./build.sh [release|debug] [--dmg]

set -euo pipefail

BUILD_TYPE="${1:-release}"
CREATE_DMG=false
if [[ "${2:-}" == "--dmg" ]] || [[ "${1:-}" == "--dmg" ]]; then
    CREATE_DMG=true
    if [[ "${1:-}" == "--dmg" ]]; then
        BUILD_TYPE="release"
    fi
fi

PRODUCT_NAME="VoiceTranscriber"
DISPLAY_NAME="Verbalize"
BUNDLE_ID="com.verbalize.app"
APP_NAME="${DISPLAY_NAME}.app"
VERSION="1.1.0"

echo "==> Building Verbalize ($BUILD_TYPE)..."

# Build with SwiftPM
if [ "$BUILD_TYPE" = "release" ]; then
    swift build -c release 2>&1
    BUILD_DIR=".build/release"
else
    swift build 2>&1
    BUILD_DIR=".build/debug"
fi

EXECUTABLE="${BUILD_DIR}/${PRODUCT_NAME}"

if [ ! -f "$EXECUTABLE" ]; then
    echo "ERROR: Build failed — executable not found at $EXECUTABLE"
    exit 1
fi

# Create .app bundle
APP_DIR="${BUILD_DIR}/${APP_NAME}"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "==> Creating app bundle at ${APP_DIR}..."

rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

# Copy executable (renamed to display name)
cp "${EXECUTABLE}" "${MACOS}/${DISPLAY_NAME}"

# Generate app icon using sips (built-in macOS tool)
generate_app_icon() {
    local ICON_DIR="${RESOURCES}/AppIcon.iconset"
    mkdir -p "${ICON_DIR}"

    # Create a simple icon using Python (available on macOS)
    python3 - "${ICON_DIR}" << 'PYEOF'
import sys, struct, zlib, os

icon_dir = sys.argv[1]

def create_png(size, filepath):
    """Create a simple app icon PNG with a gradient background and mic symbol."""
    width = height = size
    pixels = []

    for y in range(height):
        row = []
        for x in range(width):
            # Normalized coordinates
            nx = x / width
            ny = y / height

            # Rounded rectangle mask
            margin = 0.12
            corner_r = 0.22
            in_rect = True

            # Check corners
            if nx < margin + corner_r and ny < margin + corner_r:
                dx = (margin + corner_r - nx) / corner_r
                dy = (margin + corner_r - ny) / corner_r
                if dx*dx + dy*dy > 1: in_rect = False
            elif nx > 1 - margin - corner_r and ny < margin + corner_r:
                dx = (nx - (1 - margin - corner_r)) / corner_r
                dy = (margin + corner_r - ny) / corner_r
                if dx*dx + dy*dy > 1: in_rect = False
            elif nx < margin + corner_r and ny > 1 - margin - corner_r:
                dx = (margin + corner_r - nx) / corner_r
                dy = (ny - (1 - margin - corner_r)) / corner_r
                if dx*dx + dy*dy > 1: in_rect = False
            elif nx > 1 - margin - corner_r and ny > 1 - margin - corner_r:
                dx = (nx - (1 - margin - corner_r)) / corner_r
                dy = (ny - (1 - margin - corner_r)) / corner_r
                if dx*dx + dy*dy > 1: in_rect = False
            elif nx < margin or nx > 1 - margin or ny < margin or ny > 1 - margin:
                in_rect = False

            if not in_rect:
                row.extend([0, 0, 0, 0])
                continue

            # Gradient: deep blue-purple
            r = int(30 + 40 * ny)
            g = int(20 + 30 * ny)
            b = int(120 + 80 * (1 - ny))

            # Draw stylized waveform bars in center
            cx, cy = 0.5, 0.48
            bar_width = 0.028
            bar_gap = 0.055
            bars = [-2, -1, 0, 1, 2]
            bar_heights = [0.12, 0.22, 0.30, 0.22, 0.12]

            is_bar = False
            for i, bi in enumerate(bars):
                bx = cx + bi * bar_gap
                bh = bar_heights[i]
                if abs(nx - bx) < bar_width and abs(ny - cy) < bh:
                    is_bar = True
                    break

            if is_bar:
                # White bars
                r, g, b = 255, 255, 255

            row.extend([r, g, b, 255])
        pixels.append(bytes(row))

    # Build PNG
    def make_png(w, h, rows):
        def chunk(ctype, data):
            c = ctype + data
            return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

        sig = b'\x89PNG\r\n\x1a\n'
        ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
        raw = b''.join(b'\x00' + row for row in rows)
        idat = chunk(b'IDAT', zlib.compress(raw, 9))
        iend = chunk(b'IEND', b'')
        return sig + ihdr + idat + iend

    png_data = make_png(width, height, pixels)
    with open(filepath, 'wb') as f:
        f.write(png_data)

# Generate all required sizes
sizes = [16, 32, 64, 128, 256, 512, 1024]
for s in sizes:
    create_png(s, os.path.join(icon_dir, f"icon_{s}x{s}.png"))
    print(f"  Generated {s}x{s} icon")

# Create the iconset naming convention files
import shutil
mappings = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

for name, src_size in mappings.items():
    src = os.path.join(icon_dir, f"icon_{src_size}x{src_size}.png")
    dst = os.path.join(icon_dir, name)
    if src != dst:
        shutil.copy2(src, dst)

# Clean up non-standard names
for f in os.listdir(icon_dir):
    path = os.path.join(icon_dir, f)
    if f.startswith("icon_") and ("@" not in f) and f not in mappings:
        # Keep only if it matches a standard name
        if f not in mappings:
            os.remove(path)
PYEOF

    # Convert iconset to icns
    if command -v iconutil &>/dev/null; then
        iconutil -c icns "${ICON_DIR}" -o "${RESOURCES}/AppIcon.icns" 2>/dev/null && {
            echo "==> App icon generated"
            rm -rf "${ICON_DIR}"
        } || {
            echo "==> Warning: iconutil failed, app will use default icon"
            rm -rf "${ICON_DIR}"
        }
    else
        echo "==> Warning: iconutil not found, app will use default icon"
        rm -rf "${ICON_DIR}"
    fi
}

generate_app_icon

# Create Info.plist
cat > "${CONTENTS}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Verbalize needs microphone access to record your speech for transcription.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2025. All rights reserved.</string>
</dict>
</plist>
PLIST

# Copy entitlements for reference
if [ -f "VoiceTranscriber/VoiceTranscriber.entitlements" ]; then
    cp "VoiceTranscriber/VoiceTranscriber.entitlements" "${CONTENTS}/"
fi

echo ""
echo "==> App bundle created: ${APP_DIR}"

# Create DMG installer (drag-to-Applications style)
if [ "$CREATE_DMG" = true ]; then
    echo ""
    echo "==> Creating DMG installer..."

    DMG_DIR="${BUILD_DIR}/dmg_staging"
    DMG_NAME="${DISPLAY_NAME}-${VERSION}.dmg"
    DMG_PATH="${BUILD_DIR}/${DMG_NAME}"

    rm -rf "${DMG_DIR}" "${DMG_PATH}"
    mkdir -p "${DMG_DIR}"

    # Copy app bundle to staging
    cp -r "${APP_DIR}" "${DMG_DIR}/"

    # Create Applications symlink for drag-to-install
    ln -s /Applications "${DMG_DIR}/Applications"

    # Create the DMG
    hdiutil create \
        -volname "${DISPLAY_NAME}" \
        -srcfolder "${DMG_DIR}" \
        -ov -format UDZO \
        "${DMG_PATH}" 2>/dev/null

    rm -rf "${DMG_DIR}"

    echo "==> DMG created: ${DMG_PATH}"
    echo ""
    echo "    Share this DMG with users — they just open it and drag"
    echo "    Verbalize into the Applications folder."
    echo ""
fi

echo ""
echo "==> Build complete!"
echo ""
echo "    To install manually:"
echo "      cp -r \"${APP_DIR}\" /Applications/"
echo ""
echo "    To run:"
echo "      open \"${APP_DIR}\""
echo ""
echo "    To create a distributable DMG:"
echo "      ./build.sh release --dmg"
echo ""
echo "    CLEAN UNINSTALL (removes all app data):"
echo "      rm -rf /Applications/Verbalize.app"
echo "      rm -rf ~/Library/Application\\ Support/Verbalize"
echo "      defaults delete com.verbalize.app 2>/dev/null"
echo "      # Also remove from System Settings > Privacy > Accessibility"
echo ""

# Optionally copy to /Applications
read -p "    Copy to /Applications now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "/Applications/${APP_NAME}"
    cp -r "${APP_DIR}" /Applications/
    echo "    Installed to /Applications/${APP_NAME}"
    echo "    Run with: open /Applications/${APP_NAME}"
fi
