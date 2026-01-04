#!/bin/bash

# Extract IPA and get app info
# Usage: ./extract-ipa.sh <ipa_path> <output_dir>

set -e

IPA_PATH=$1
OUTPUT_DIR=${2:-"extracted"}

if [ -z "$IPA_PATH" ]; then
    echo "Error: IPA path is required"
    exit 1
fi

if [ ! -f "$IPA_PATH" ]; then
    echo "Error: IPA file not found: $IPA_PATH"
    exit 1
fi

echo "==================================="
echo "  Extracting IPA"
echo "==================================="
echo ""
echo "IPA: $IPA_PATH"
echo "Output: $OUTPUT_DIR"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Extract IPA (it's a ZIP file)
echo "Extracting..."
unzip -q "$IPA_PATH" -d "$OUTPUT_DIR"

# Find the .app bundle
APP_PATH=$(find "$OUTPUT_DIR/Payload" -name "*.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Error: No .app found in IPA"
    exit 1
fi

echo "App found: $APP_PATH"
echo ""

# Extract app info from Info.plist
INFO_PLIST="$APP_PATH/Info.plist"

if [ ! -f "$INFO_PLIST" ]; then
    echo "Error: Info.plist not found"
    exit 1
fi

echo "==================================="
echo "  App Information"
echo "==================================="
echo ""

# Get bundle identifier
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$INFO_PLIST")
echo "Bundle ID: $BUNDLE_ID"

# Get version
VERSION=$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")
echo "Version: $VERSION"

# Get build number
BUILD_NUMBER=$(plutil -extract CFBundleVersion raw "$INFO_PLIST")
echo "Build: $BUILD_NUMBER"

# Get display name (optional)
DISPLAY_NAME=$(plutil -extract CFBundleDisplayName raw "$INFO_PLIST" 2>/dev/null || echo "")
if [ -n "$DISPLAY_NAME" ]; then
    echo "Display Name: $DISPLAY_NAME"
fi

# Get minimum iOS version
MIN_IOS=$(plutil -extract MinimumOSVersion raw "$INFO_PLIST" 2>/dev/null || echo "")
if [ -n "$MIN_IOS" ]; then
    echo "Minimum iOS: $MIN_IOS"
fi

# Get supported devices
DEVICE_FAMILY=$(plutil -extract UIDeviceFamily raw "$INFO_PLIST" 2>/dev/null || echo "")
if [ -n "$DEVICE_FAMILY" ]; then
    echo "Device Family: $DEVICE_FAMILY"
fi

echo ""
echo "==================================="
echo "  Extraction Complete"
echo "==================================="

# Output info as JSON for scripts
cat > "$OUTPUT_DIR/app-info.json" << EOF
{
    "bundleId": "$BUNDLE_ID",
    "version": "$VERSION",
    "buildNumber": "$BUILD_NUMBER",
    "displayName": "$DISPLAY_NAME",
    "minimumOSVersion": "$MIN_IOS",
    "appPath": "$APP_PATH"
}
EOF

echo ""
echo "App info saved to: $OUTPUT_DIR/app-info.json"

