#!/bin/bash
# Build VoiceTranscriber as a macOS .app bundle
# Usage: ./build.sh [release|debug]

set -euo pipefail

BUILD_TYPE="${1:-release}"
PRODUCT_NAME="VoiceTranscriber"
BUNDLE_ID="com.voicetranscriber.app"
APP_NAME="${PRODUCT_NAME}.app"

echo "==> Building VoiceTranscriber ($BUILD_TYPE)..."

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

# Copy executable
cp "${EXECUTABLE}" "${MACOS}/${PRODUCT_NAME}"

# Create Info.plist
cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>VoiceTranscriber</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.voicetranscriber.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>VoiceTranscriber</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceTranscriber needs microphone access to record your speech for transcription.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2024. All rights reserved.</string>
</dict>
</plist>
PLIST

# Copy entitlements for reference (not enforced without codesigning)
if [ -f "VoiceTranscriber/VoiceTranscriber.entitlements" ]; then
    cp "VoiceTranscriber/VoiceTranscriber.entitlements" "${CONTENTS}/"
fi

echo ""
echo "==> Build complete!"
echo ""
echo "    App bundle: ${APP_DIR}"
echo ""
echo "    To install:"
echo "      cp -r \"${APP_DIR}\" /Applications/"
echo ""
echo "    To run:"
echo "      open \"${APP_DIR}\""
echo ""
echo "    After first launch, grant Microphone and Accessibility permissions"
echo "    in System Settings > Privacy & Security."
echo ""

# Optionally copy to /Applications
read -p "    Copy to /Applications? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "/Applications/${APP_NAME}"
    cp -r "${APP_DIR}" /Applications/
    echo "    Installed to /Applications/${APP_NAME}"
    echo "    Run with: open /Applications/${APP_NAME}"
fi
