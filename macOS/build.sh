#!/bin/bash
# Copyright (c) 2026 Siyuan Wang.
# Licensed under the GNU General Public License v3. See LICENSE.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${BITBOT_BUILD_ROOT:-$PROJECT_ROOT/.build}"
OUTPUT_DIR="${BITBOT_OUTPUT_DIR:-$PROJECT_ROOT/macOS/output}"
CONFIGURATION="${BITBOT_CONFIGURATION:-release}"

if [[ "$(uname -s)" != Darwin ]]; then
    echo "Bitbot Copilot requires macOS 14 or later." >&2
    exit 1
fi

export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/swift-cache"
SWIFT_FLAGS=(--package-path "$PROJECT_ROOT" --scratch-path "$BUILD_ROOT"
    --cache-path "$BUILD_ROOT/cache" --config-path "$BUILD_ROOT/config"
    --security-path "$BUILD_ROOT/security" --disable-sandbox -c "$CONFIGURATION")
if [[ "${BITBOT_UNIVERSAL:-0}" == 1 ]]; then
    SWIFT_FLAGS+=(--arch arm64 --arch x86_64)
fi

swift build "${SWIFT_FLAGS[@]}"
BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"
APP_PATH="$OUTPUT_DIR/Bitbot Copilot.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/BitbotCopilot" "$APP_PATH/Contents/MacOS/BitbotCopilot.next"
mv -f "$APP_PATH/Contents/MacOS/BitbotCopilot.next" "$APP_PATH/Contents/MacOS/BitbotCopilot"
cp "$PROJECT_ROOT/macOS/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_ROOT/macOS/Sources/BitbotCopilot/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp -R "$BIN_DIR/BitbotCopilot_BitbotCopilot.bundle" "$APP_PATH/Contents/Resources/"
# Folder resources may retain deleted files in incremental build outputs.
RESOURCE_ROOT="$APP_PATH/Contents/Resources/BitbotCopilot_BitbotCopilot.bundle"
if [[ -d "$RESOURCE_ROOT/Contents/Resources" ]]; then
    RESOURCE_ROOT="$RESOURCE_ROOT/Contents/Resources"
fi
/usr/bin/rsync -a --delete "$PROJECT_ROOT/macOS/Sources/BitbotCopilot/Resources/Legal/" "$RESOURCE_ROOT/Legal/"
/usr/bin/codesign --force --sign - "$APP_PATH"
echo "Built: $APP_PATH"
