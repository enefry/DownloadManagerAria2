#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/libaria2-build-common.sh"

ARTIFACT_DIR="$ROOT_DIR/artifacts/libaria2"
XCFRAMEWORK="$ARTIFACT_DIR/libaria2.xcframework"
SMOKE_SRC="$ROOT_DIR/Tests/libaria2-smoke/main.cc"
SWIFT_SMOKE_SRC="$ROOT_DIR/Tests/libaria2-smoke/swift_smoke.swift"
SWIFT_MODULE_CACHE="/private/tmp/libaria2-swift-module-cache"

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "missing required file: $1" >&2
    exit 1
  fi
}

assert_config_defined() {
  local config="$1"
  local macro="$2"

  if ! grep -Eq "^#define[[:space:]]+$macro([[:space:]]+|$)" "$config"; then
    echo "$config does not define $macro" >&2
    exit 1
  fi
}

assert_config_undefined() {
  local config="$1"
  local macro="$2"

  if grep -Eq "^#define[[:space:]]+$macro([[:space:]]+|$)" "$config"; then
    echo "$config unexpectedly defines $macro" >&2
    exit 1
  fi
}

assert_trimmed_config() {
  local config="$1"

  assert_config_defined "$config" ENABLE_BITTORRENT
  assert_config_defined "$config" HAVE_APPLETLS
  assert_config_defined "$config" USE_APPLE_MD

  assert_config_undefined "$config" ENABLE_METALINK
  assert_config_undefined "$config" ENABLE_WEBSOCKET
  assert_config_undefined "$config" ENABLE_XML_RPC
  assert_config_undefined "$config" HAVE_LIBCARES
  assert_config_undefined "$config" HAVE_LIBEXPAT
  assert_config_undefined "$config" HAVE_LIBSSH2
  assert_config_undefined "$config" HAVE_LIBXML2
  assert_config_undefined "$config" HAVE_SQLITE3
  assert_config_undefined "$config" HAVE_ZLIB
}

require_file "$XCFRAMEWORK/Info.plist"
require_file "$SMOKE_SRC"
require_file "$SWIFT_SMOKE_SRC"
mkdir -p "$SWIFT_MODULE_CACHE"

for slice in macos-arm64 ios-arm64 ios-simulator-arm64; do
  require_file "$ARTIFACT_DIR/$slice/lib/libaria2.0.dylib"
  require_file "$ARTIFACT_DIR/$slice/include/aria2/aria2.h"
  require_file "$ARTIFACT_DIR/$slice/include/DMAria2.h"
  require_file "$ARTIFACT_DIR/$slice/include/module.modulemap"
  echo "== $slice dynamic dependencies =="
  otool -L "$ARTIFACT_DIR/$slice/lib/libaria2.0.dylib"
  libaria2_assert_system_dynamic_dependencies "$ARTIFACT_DIR/$slice/lib/libaria2.0.dylib"
  libaria2_assert_no_third_party_exports "$ARTIFACT_DIR/$slice/lib/libaria2.0.dylib"
  libaria2_assert_objc_exports "$ARTIFACT_DIR/$slice/lib/libaria2.0.dylib"
  libaria2_assert_limited_aria2_exports "$ARTIFACT_DIR/$slice/lib/libaria2.0.dylib"
  if [[ -f "$ROOT_DIR/build/libaria2-$slice/config.h" ]]; then
    assert_trimmed_config "$ROOT_DIR/build/libaria2-$slice/config.h"
  else
    echo "Skipping config.h feature-profile check for $slice; build/libaria2-$slice/config.h is not present."
  fi
done

echo "== XCFramework Info.plist =="
plutil -p "$XCFRAMEWORK/Info.plist"

echo "== platform load commands =="
vtool -show-build "$ARTIFACT_DIR/macos-arm64/lib/libaria2.0.dylib"
vtool -show-build "$ARTIFACT_DIR/ios-arm64/lib/libaria2.0.dylib"
vtool -show-build "$ARTIFACT_DIR/ios-simulator-arm64/lib/libaria2.0.dylib"

echo "== macOS smoke =="
clang++ -std=c++11 -arch arm64 \
  -I"$XCFRAMEWORK/macos-arm64/Headers" \
  "$SMOKE_SRC" \
  "$XCFRAMEWORK/macos-arm64/libaria2.0.dylib" \
  -Wl,-rpath,"$XCFRAMEWORK/macos-arm64" \
  -o /private/tmp/libaria2_xcframework_macos_smoke
/private/tmp/libaria2_xcframework_macos_smoke

echo "== macOS ObjC wrapper smoke =="
clang++ -std=c++11 -fobjc-arc -fblocks -arch arm64 \
  -I"$XCFRAMEWORK/macos-arm64/Headers" \
  "$ROOT_DIR/Tests/libaria2-smoke/objc_smoke.mm" \
  "$XCFRAMEWORK/macos-arm64/libaria2.0.dylib" \
  -framework Foundation \
  -Wl,-rpath,"$XCFRAMEWORK/macos-arm64" \
  -o /private/tmp/libaria2_xcframework_objc_macos_smoke
/private/tmp/libaria2_xcframework_objc_macos_smoke

echo "== macOS Swift wrapper smoke =="
swiftc -target arm64-apple-macosx13.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path "$SWIFT_MODULE_CACHE" \
  -I"$XCFRAMEWORK/macos-arm64/Headers" \
  "$SWIFT_SMOKE_SRC" \
  "$XCFRAMEWORK/macos-arm64/libaria2.0.dylib" \
  -Xlinker -rpath -Xlinker "$XCFRAMEWORK/macos-arm64" \
  -o /private/tmp/libaria2_xcframework_swift_macos_smoke
/private/tmp/libaria2_xcframework_swift_macos_smoke

echo "== iOS device link =="
clang++ -std=c++11 -target arm64-apple-ios15.0 \
  -fobjc-arc -fblocks \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -I"$XCFRAMEWORK/ios-arm64/Headers" \
  "$ROOT_DIR/Tests/libaria2-smoke/objc_smoke.mm" \
  "$XCFRAMEWORK/ios-arm64/libaria2.0.dylib" \
  -framework Foundation -framework CoreFoundation -framework Security -lc++ \
  -o /private/tmp/libaria2_xcframework_ios_link

echo "== iOS device Swift import =="
swiftc -target arm64-apple-ios15.0 \
  -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -module-cache-path "$SWIFT_MODULE_CACHE" \
  -I"$XCFRAMEWORK/ios-arm64/Headers" \
  "$SWIFT_SMOKE_SRC" \
  -typecheck

echo "== iOS simulator link =="
clang++ -std=c++11 -target arm64-apple-ios15.0-simulator \
  -fobjc-arc -fblocks \
  -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -I"$XCFRAMEWORK/ios-arm64-simulator/Headers" \
  "$ROOT_DIR/Tests/libaria2-smoke/objc_smoke.mm" \
  "$XCFRAMEWORK/ios-arm64-simulator/libaria2.0.dylib" \
  -framework Foundation -framework CoreFoundation -framework Security -lc++ \
  -o /private/tmp/libaria2_xcframework_iossim_link

echo "== iOS simulator Swift import =="
swiftc -target arm64-apple-ios15.0-simulator \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -module-cache-path "$SWIFT_MODULE_CACHE" \
  -I"$XCFRAMEWORK/ios-arm64-simulator/Headers" \
  "$SWIFT_SMOKE_SRC" \
  -typecheck

echo "libaria2 XCFramework verification ok"
