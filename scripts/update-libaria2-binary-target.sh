#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/update-libaria2-binary-target.sh <zip-url> <swiftpm-checksum>

Updates Package.swift's default remote libaria2 binary target URL and checksum.
USAGE
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

URL="$1"
CHECKSUM="$2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/Package.swift"

if [[ ! "$CHECKSUM" =~ ^[0-9a-f]{64}$ ]]; then
  echo "checksum must be a 64-character lowercase hex SwiftPM checksum" >&2
  exit 1
fi

LIBARIA2_BINARY_URL="$URL" \
LIBARIA2_BINARY_CHECKSUM="$CHECKSUM" \
perl -0pi -e '
  s|let defaultLibaria2BinaryURL = ".*?"|let defaultLibaria2BinaryURL = "$ENV{LIBARIA2_BINARY_URL}"|;
  s|let defaultLibaria2BinaryChecksum = ".*?"|let defaultLibaria2BinaryChecksum = "$ENV{LIBARIA2_BINARY_CHECKSUM}"|;
' "$MANIFEST"

echo "Updated $MANIFEST"
