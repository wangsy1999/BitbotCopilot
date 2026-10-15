#!/bin/bash
# Copyright (c) 2026 Siyuan Wang.
# Licensed under the GNU General Public License v3. See LICENSE.

set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RENDER_PACKAGE="$(mktemp -d "${TMPDIR:-/tmp}/bitbot-docs.XXXXXX")"
trap 'rm -rf "$RENDER_PACKAGE"' EXIT
mkdir -p "$RENDER_PACKAGE/Sources/BitbotCopilot" "$RENDER_PACKAGE/Sources/BitbotCore"
cp "$PROJECT_ROOT"/macOS/Sources/BitbotCore/*.swift "$RENDER_PACKAGE/Sources/BitbotCore/"
for source in "$PROJECT_ROOT"/macOS/Sources/BitbotCopilot/*.swift; do
    if [[ "$(basename "$source")" != BitbotCopilotApp.swift ]]; then
        cp "$source" "$RENDER_PACKAGE/Sources/BitbotCopilot/"
    fi
done
cp -R "$PROJECT_ROOT/macOS/Sources/BitbotCopilot/Resources" "$RENDER_PACKAGE/Sources/BitbotCopilot/"
cp "$PROJECT_ROOT/macOS/Tools/RenderDocumentation.swift" "$RENDER_PACKAGE/Sources/BitbotCopilot/"
cat > "$RENDER_PACKAGE/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Documentation", platforms: [.macOS(.v14)], targets: [
    .target(name: "BitbotCore"),
    .executableTarget(name: "BitbotCopilot", dependencies: ["BitbotCore"], resources: [.copy("Resources/AppIcon.icns"), .copy("Resources/Legal")])
])
SWIFT
export CLANG_MODULE_CACHE_PATH="$RENDER_PACKAGE/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$RENDER_PACKAGE/swift-cache"
swift run --package-path "$RENDER_PACKAGE" --scratch-path "$RENDER_PACKAGE/build" \
    --cache-path "$RENDER_PACKAGE/cache" --config-path "$RENDER_PACKAGE/config" \
    --security-path "$RENDER_PACKAGE/security" --disable-sandbox \
    BitbotCopilot "$PROJECT_ROOT" "$PROJECT_ROOT/doc/screenshots"
