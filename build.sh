#!/usr/bin/env bash
# ==============================================================================
# build.sh — Native macOS Website-to-App Wrapper Generator (Backed by ./pwa)
# Usage: ./build.sh <website_url> <icon_path> <output_app_path> [dark|light|system]
# Example: ./build.sh "https://www.google.com" "google.icns" "./google.app" "dark"
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PWA_PROJECT_DIR="$SCRIPT_DIR/pwa"

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "Usage: $0 <website_url> <icon_path> <output_app_path> [dark|light|system]"
    echo "Example: $0 \"https://www.google.com\" \"google.icns\" \"./google.app\" \"dark\""
    exit 1
fi

TARGET_URL="$1"
ICON_INPUT="$2"
OUTPUT_INPUT="$3"
THEME_MODE="${4:-system}"

# Normalize and validate theme parameter
THEME_MODE="$(echo "$THEME_MODE" | tr '[:upper:]' '[:lower:]')"
if [[ "$THEME_MODE" != "dark" && "$THEME_MODE" != "light" && "$THEME_MODE" != "system" ]]; then
    echo "Error: Invalid theme mode '$THEME_MODE'. Expected 'dark', 'light', or 'system'."
    exit 1
fi

# Validate URL scheme (allow empty URL "" for a blank startup window)
if [[ -n "$TARGET_URL" && ! "$TARGET_URL" =~ ^https?:// ]]; then
    echo "Error: First parameter must be a valid http:// or https:// URL, or empty \"\" (got: $TARGET_URL)"
    exit 1
fi

# Resolve Icon Path (check current directory first, then script directory or ./icons/)
if [ ! -f "$ICON_INPUT" ]; then
    if [ -f "$SCRIPT_DIR/$ICON_INPUT" ]; then
        ICON_INPUT="$SCRIPT_DIR/$ICON_INPUT"
    elif [ -f "$SCRIPT_DIR/icons/$ICON_INPUT" ]; then
        ICON_INPUT="$SCRIPT_DIR/icons/$ICON_INPUT"
    else
        echo "Error: Icon file not found at '$ICON_INPUT'"
        exit 1
    fi
fi

# Normalize output path so it always ends with .app
if [[ "$OUTPUT_INPUT" != *.app ]]; then
    OUTPUT_INPUT="${OUTPUT_INPUT}.app"
fi

# Resolve absolute path for output .app bundle
mkdir -p "$(dirname "$OUTPUT_INPUT")"
OUTPUT_PARENT_DIR="$(cd "$(dirname "$OUTPUT_INPUT")" && pwd)"
APP_BUNDLE_NAME="$(basename "$OUTPUT_INPUT")"
APP_NAME="${APP_BUNDLE_NAME%.app}"
APP_DIR="${OUTPUT_PARENT_DIR}/${APP_BUNDLE_NAME}"

CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Generate a unique, valid macOS Bundle Identifier from the URL host + app name
SAFE_NAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/./g' | sed 's/\.\.*/./g' | sed 's/^\.//;s/\.$//')
if [ -z "$SAFE_NAME" ]; then
    SAFE_NAME="webapp"
fi
BUNDLE_ID="com.app.${SAFE_NAME}"

echo "==> Building macOS App: ${APP_NAME}"
echo "    Project:    ${PWA_PROJECT_DIR}"
echo "    URL:        ${TARGET_URL}"
echo "    Icon:       ${ICON_INPUT}"
echo "    Output:     ${APP_DIR}"
echo "    Theme:      ${THEME_MODE}"
echo "    Bundle ID:  ${BUNDLE_ID}"

# Gracefully stop running instance if rebuilding the same app
pkill -f "${APP_DIR}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true

# Create .app directory hierarchy
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# ==============================================================================
# Icon Handling (Supports .icns directly, or converts .png/.jpg/.jpeg to .icns)
# ==============================================================================
ICON_EXT="${ICON_INPUT##*.}"
ICON_EXT_LOWER=$(echo "$ICON_EXT" | tr '[:upper:]' '[:lower:]')

if [ "$ICON_EXT_LOWER" = "icns" ]; then
    cp "$ICON_INPUT" "$RESOURCES_DIR/AppIcon.icns"
else
    echo "==> Converting $ICON_INPUT to AppIcon.icns..."
    TMP_ICONSET_DIR=$(mktemp -d)
    ICONSET_PATH="${TMP_ICONSET_DIR}/AppIcon.iconset"
    mkdir -p "$ICONSET_PATH"

    sips -z 16 16     "$ICON_INPUT" --out "${ICONSET_PATH}/icon_16x16.png"      >/dev/null 2>&1
    sips -z 32 32     "$ICON_INPUT" --out "${ICONSET_PATH}/icon_16x16@2x.png"   >/dev/null 2>&1
    sips -z 32 32     "$ICON_INPUT" --out "${ICONSET_PATH}/icon_32x32.png"      >/dev/null 2>&1
    sips -z 64 64     "$ICON_INPUT" --out "${ICONSET_PATH}/icon_32x32@2x.png"   >/dev/null 2>&1
    sips -z 128 128   "$ICON_INPUT" --out "${ICONSET_PATH}/icon_128x128.png"    >/dev/null 2>&1
    sips -z 256 256   "$ICON_INPUT" --out "${ICONSET_PATH}/icon_128x128@2x.png" >/dev/null 2>&1
    sips -z 256 256   "$ICON_INPUT" --out "${ICONSET_PATH}/icon_256x256.png"    >/dev/null 2>&1
    sips -z 512 512   "$ICON_INPUT" --out "${ICONSET_PATH}/icon_256x256@2x.png" >/dev/null 2>&1
    sips -z 512 512   "$ICON_INPUT" --out "${ICONSET_PATH}/icon_512x512.png"    >/dev/null 2>&1
    sips -z 1024 1024 "$ICON_INPUT" --out "${ICONSET_PATH}/icon_512x512@2x.png" >/dev/null 2>&1

    if iconutil -c icns "$ICONSET_PATH" -o "$RESOURCES_DIR/AppIcon.icns" >/dev/null 2>&1; then
        echo "    Successfully converted to .icns"
    else
        cp "$ICON_INPUT" "$RESOURCES_DIR/AppIcon.icns"
    fi
    rm -rf "$TMP_ICONSET_DIR"
fi

# ==============================================================================
# Generate Info.plist (Passes PWATargetURL and PWAThemeMode to the pwa binary)
# ==============================================================================
cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>PWATargetURL</key>
    <string>${TARGET_URL}</string>
    <key>PWAThemeMode</key>
    <string>${THEME_MODE}</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

# ==============================================================================
# Build the Swift macOS Project in ./pwa
# ==============================================================================
echo "==> Compiling Swift project (pwa)..."
swift build -c release --package-path "$PWA_PROJECT_DIR"
BIN_PATH="$(swift build -c release --package-path "$PWA_PROJECT_DIR" --show-bin-path)/pwa"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Sign with stable identifier so macOS Keychain & permissions recognize the app across rebuilds
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_DIR" 2>/dev/null || true

# Refresh Finder / Dock icon cache
touch "$APP_DIR"

echo "==> Successfully created: $APP_DIR"
# echo "==> Launching ${APP_NAME}..."
# open "$APP_DIR"
