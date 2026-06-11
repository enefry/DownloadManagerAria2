#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCFRAMEWORK="$ROOT_DIR/artifacts/libaria2/libaria2.xcframework"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE_NAME="${LIBARIA2_ARCHIVE_NAME:-libaria2.xcframework.zip}"
ARCHIVE="$DIST_DIR/$ARCHIVE_NAME"

if [[ ! -d "$XCFRAMEWORK" ]]; then
  echo "missing XCFramework: $XCFRAMEWORK" >&2
  echo "run scripts/build-libaria2-xcframework.sh first" >&2
  exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

pushd "$(dirname "$XCFRAMEWORK")" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$(basename "$XCFRAMEWORK")" "$ARCHIVE"
popd >/dev/null

swift package compute-checksum "$ARCHIVE" > "$ARCHIVE.checksum"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"

echo "Archive: $ARCHIVE"
echo "SwiftPM checksum: $(cat "$ARCHIVE.checksum")"
