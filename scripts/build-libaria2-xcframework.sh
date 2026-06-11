#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/libaria2"
XCFRAMEWORK="$ARTIFACT_DIR/libaria2.xcframework"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  "$ROOT_DIR/scripts/build-libaria2-macos-arm64.sh"
  "$ROOT_DIR/scripts/build-libaria2-ios.sh"
fi

rm -rf "$XCFRAMEWORK"

xcodebuild -create-xcframework \
  -library "$ARTIFACT_DIR/macos-arm64/lib/libaria2.0.dylib" \
  -headers "$ARTIFACT_DIR/macos-arm64/include" \
  -library "$ARTIFACT_DIR/ios-arm64/lib/libaria2.0.dylib" \
  -headers "$ARTIFACT_DIR/ios-arm64/include" \
  -library "$ARTIFACT_DIR/ios-simulator-arm64/lib/libaria2.0.dylib" \
  -headers "$ARTIFACT_DIR/ios-simulator-arm64/include" \
  -output "$XCFRAMEWORK"

echo "Built: $XCFRAMEWORK"
plutil -p "$XCFRAMEWORK/Info.plist"
