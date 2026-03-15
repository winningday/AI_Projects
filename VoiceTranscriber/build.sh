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
    local SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    local SOURCE_ICON="${SCRIPT_DIR}/icon.png"
    mkdir -p "${ICON_DIR}"

    if [ ! -f "${SOURCE_ICON}" ]; then
        echo "==> Warning: icon.png not found, skipping icon generation"
        return
    fi

    echo "==> Generating app icon from icon.png..."

    # The source icon.png is 1380x752 (banner with icon in center)
    # Extract the center square (the app icon portion) using sips + python
    local TEMP_SQUARE="${ICON_DIR}/_temp_square.png"

    # Crop center square from the banner image using python
    python3 - "${SOURCE_ICON}" "${TEMP_SQUARE}" << 'PYEOF'
import sys, struct, zlib

src_path = sys.argv[1]
dst_path = sys.argv[2]

with open(src_path, 'rb') as f:
    data = f.read()

# Parse PNG to get raw pixels
# Read IHDR
w, h = struct.unpack('>II', data[16:24])
print(f"  Source: {w}x{h}")

# The icon is centered in the banner image
# Crop a square from center, using height as the square size (with some padding)
sq = min(w, h)
# Add some top/bottom margin to focus on the icon
margin_y = int(sq * 0.03)
margin_x = int((w - sq) / 2)

# For the crop, we'll use sips on macOS, so just write coords
# Output the crop coordinates for sips
crop_size = h - (margin_y * 2)
print(f"  Cropping to {crop_size}x{crop_size} square from center")

# Write crop info for the shell script to use
with open(dst_path + '.crop', 'w') as f:
    f.write(f"{crop_size} {margin_x + (w - crop_size)//2 - margin_x} {margin_y}")
PYEOF

    # Read crop params and use sips (macOS built-in) to crop and resize
    if [ -f "${TEMP_SQUARE}.crop" ]; then
        read CROP_SIZE CROP_X CROP_Y < "${TEMP_SQUARE}.crop"
        rm "${TEMP_SQUARE}.crop"

        # Copy source and crop with sips
        cp "${SOURCE_ICON}" "${TEMP_SQUARE}"
        # Crop to square from center: first pad, then cropToHeightWidth
        sips -c "${CROP_SIZE}" "${CROP_SIZE}" "${TEMP_SQUARE}" --out "${TEMP_SQUARE}" 2>/dev/null

        # Generate all required iconset sizes
        for size in 16 32 64 128 256 512 1024; do
            sips -z "${size}" "${size}" "${TEMP_SQUARE}" --out "${ICON_DIR}/icon_${size}.png" 2>/dev/null
        done

        # Create iconset naming convention
        cp "${ICON_DIR}/icon_16.png"   "${ICON_DIR}/icon_16x16.png"
        cp "${ICON_DIR}/icon_32.png"   "${ICON_DIR}/icon_16x16@2x.png"
        cp "${ICON_DIR}/icon_32.png"   "${ICON_DIR}/icon_32x32.png"
        cp "${ICON_DIR}/icon_64.png"   "${ICON_DIR}/icon_32x32@2x.png"
        cp "${ICON_DIR}/icon_128.png"  "${ICON_DIR}/icon_128x128.png"
        cp "${ICON_DIR}/icon_256.png"  "${ICON_DIR}/icon_128x128@2x.png"
        cp "${ICON_DIR}/icon_256.png"  "${ICON_DIR}/icon_256x256.png"
        cp "${ICON_DIR}/icon_512.png"  "${ICON_DIR}/icon_256x256@2x.png"
        cp "${ICON_DIR}/icon_512.png"  "${ICON_DIR}/icon_512x512.png"
        cp "${ICON_DIR}/icon_1024.png" "${ICON_DIR}/icon_512x512@2x.png"

        # Clean up temp files
        rm -f "${TEMP_SQUARE}" "${ICON_DIR}"/icon_[0-9]*.png
    fi

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
