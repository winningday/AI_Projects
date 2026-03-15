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

# Generate app icon from icon.png using sips (built-in macOS tool)
# This runs in a subshell so failures don't kill the whole build
(
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    SOURCE_ICON="${SCRIPT_DIR}/icon.png"
    ICON_DIR="${RESOURCES}/AppIcon.iconset"

    if [ ! -f "${SOURCE_ICON}" ]; then
        echo "==> Warning: icon.png not found at ${SOURCE_ICON}, skipping icon"
        exit 0
    fi

    echo "==> Generating app icon from icon.png..."
    mkdir -p "${ICON_DIR}"

    # Make the icon full-bleed: extend the background to fill the entire 1024x1024
    # canvas edge-to-edge. macOS applies its own squircle mask automatically.
    # Without this, baked-in rounded corners create a white border artifact.
    FULLBLEED_ICON="${ICON_DIR}/_fullbleed.png"
    swift - "${SOURCE_ICON}" "${FULLBLEED_ICON}" << 'SWIFT_FULLBLEED'
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

// Sample the background color from the center-top area of the icon
// (safely inside the rounded-rect region of the original icon)
let sampleRep = NSBitmapImageRep(data: srcImage.tiffRepresentation!)!
// Sample at ~50% x, ~90% y (top-center, well inside the dark background)
let sx = sampleRep.pixelsWide / 2
let sy = Int(Double(sampleRep.pixelsHigh) * 0.9)
let bgColor = sampleRep.colorAt(x: sx, y: sy) ?? NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0)

// Fill entire canvas with the sampled background color
bgColor.setFill()
rect.fill()

// Draw the original icon on top — its transparent corners blend seamlessly
srcImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Error: cannot create PNG\n", stderr)
    exit(1)
}
try! pngData.write(to: URL(fileURLWithPath: args[2]))
SWIFT_FULLBLEED

    if [ ! -f "${FULLBLEED_ICON}" ]; then
        echo "==> Warning: full-bleed step failed, falling back to raw icon"
        FULLBLEED_ICON="${SOURCE_ICON}"
    fi

    # Source is the full-bleed 1024x1024 square PNG (no transparency)
    TEMP="${ICON_DIR}/_source.png"
    cp "${FULLBLEED_ICON}" "${TEMP}"

    # Generate all required iconset sizes
    for size in 16 32 64 128 256 512 1024; do
        sips -z "${size}" "${size}" "${TEMP}" --out "${ICON_DIR}/_s${size}.png" >/dev/null 2>&1
    done
    rm -f "${TEMP}"

    # Create iconset with Apple's required naming convention
    cp "${ICON_DIR}/_s16.png"   "${ICON_DIR}/icon_16x16.png"
    cp "${ICON_DIR}/_s32.png"   "${ICON_DIR}/icon_16x16@2x.png"
    cp "${ICON_DIR}/_s32.png"   "${ICON_DIR}/icon_32x32.png"
    cp "${ICON_DIR}/_s64.png"   "${ICON_DIR}/icon_32x32@2x.png"
    cp "${ICON_DIR}/_s128.png"  "${ICON_DIR}/icon_128x128.png"
    cp "${ICON_DIR}/_s256.png"  "${ICON_DIR}/icon_128x128@2x.png"
    cp "${ICON_DIR}/_s256.png"  "${ICON_DIR}/icon_256x256.png"
    cp "${ICON_DIR}/_s512.png"  "${ICON_DIR}/icon_256x256@2x.png"
    cp "${ICON_DIR}/_s512.png"  "${ICON_DIR}/icon_512x512.png"
    cp "${ICON_DIR}/_s1024.png" "${ICON_DIR}/icon_512x512@2x.png"

    # Clean up temp sized files
    rm -f "${ICON_DIR}"/_s*.png "${ICON_DIR}/_fullbleed.png"

    # Convert iconset to icns
    if iconutil -c icns "${ICON_DIR}" -o "${RESOURCES}/AppIcon.icns" 2>/dev/null; then
        echo "==> App icon generated successfully"
    else
        echo "==> Warning: iconutil failed, app will use default icon"
    fi
    rm -rf "${ICON_DIR}"
) || echo "==> Warning: Icon generation failed, continuing without custom icon..."

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
