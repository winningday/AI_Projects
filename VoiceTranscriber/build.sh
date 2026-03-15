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
VERSION="1.2.0"

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

# Generate app icon using make-icon.sh
# The --fix-corners flag handles source images with baked-in rounded corners
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_ICON="${SCRIPT_DIR}/icon.png"

if [ -f "${SOURCE_ICON}" ]; then
    "${SCRIPT_DIR}/make-icon.sh" --fix-corners "${SOURCE_ICON}" "${RESOURCES}/AppIcon.icns" \
        || echo "==> Warning: Icon generation failed, continuing without custom icon..."
else
    echo "==> Warning: icon.png not found, skipping icon generation"
fi

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
    <string>3</string>
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
