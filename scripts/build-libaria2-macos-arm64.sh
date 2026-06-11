#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/libaria2-build-common.sh"

ARIA2_DIR="$ROOT_DIR/third_party/aria2"
BUILD_DIR="$ROOT_DIR/build/libaria2-macos-arm64"
INSTALL_DIR="$ROOT_DIR/artifacts/libaria2/macos-arm64"
EXPORTS_FILE="$BUILD_DIR/libaria2.exports"

libaria2_ensure_upstream_source "$ROOT_DIR"

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
NCPU="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
export SDKROOT MACOSX_DEPLOYMENT_TARGET

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "missing required file: $1" >&2
    exit 1
  fi
}

require_file "$ARIA2_DIR/configure.ac"

rm -rf "$BUILD_DIR" "$INSTALL_DIR"
mkdir -p "$BUILD_DIR" "$INSTALL_DIR/include/aria2" "$INSTALL_DIR/lib"

pushd "$ARIA2_DIR" >/dev/null
if [[ ! -x ./configure ]]; then
  autoreconf -fi
fi
popd >/dev/null

export PKG_CONFIG="${PKG_CONFIG:-pkg-config}"
export PKG_CONFIG_PATH=
export PKG_CONFIG_LIBDIR=
export CC="${CC:-clang}"
export CXX="${CXX:-clang++}"

COMMON_FLAGS="-arch arm64 -isysroot $SDKROOT -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
export CFLAGS="${CFLAGS:-$COMMON_FLAGS}"
export CXXFLAGS="${CXXFLAGS:-$COMMON_FLAGS -std=c++11}"
export CPPFLAGS="${CPPFLAGS:-}"
BASE_LDFLAGS="-arch arm64 -isysroot $SDKROOT -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
export LDFLAGS="${LDFLAGS:-$BASE_LDFLAGS}"

pushd "$BUILD_DIR" >/dev/null
"$ARIA2_DIR/configure" \
  --prefix="$INSTALL_DIR" \
  "${LIBARIA2_COMMON_CONFIGURE_ARGS[@]}"

make -C src -j"$NCPU" libaria2.la

WRAPPER_OBJECT="$(
  libaria2_compile_objc_wrapper \
    "$ROOT_DIR" \
    "$ARIA2_DIR" \
    "$BUILD_DIR" \
    "$CXX" \
    "$COMMON_FLAGS"
)"
libaria2_generate_exports_file "$BUILD_DIR/src/.libs/libaria2.0.dylib" "$EXPORTS_FILE"

mkdir -p "$INSTALL_DIR/include/aria2" "$INSTALL_DIR/lib"
libaria2_link_dylib_with_objc_wrapper \
  "$BUILD_DIR" \
  "$INSTALL_DIR/lib/libaria2.0.dylib" \
  "$WRAPPER_OBJECT" \
  "$CXX" \
  "$BASE_LDFLAGS" \
  "$EXPORTS_FILE"
ln -sf libaria2.0.dylib "$INSTALL_DIR/lib/libaria2.dylib"
libaria2_install_public_headers "$ROOT_DIR" "$ARIA2_DIR" "$INSTALL_DIR"
popd >/dev/null

echo "Built: $INSTALL_DIR/lib/libaria2.0.dylib"
file "$INSTALL_DIR/lib/libaria2.0.dylib"
otool -L "$INSTALL_DIR/lib/libaria2.0.dylib"
libaria2_assert_no_third_party_exports "$INSTALL_DIR/lib/libaria2.0.dylib"
libaria2_assert_system_dynamic_dependencies "$INSTALL_DIR/lib/libaria2.0.dylib"
libaria2_assert_objc_exports "$INSTALL_DIR/lib/libaria2.0.dylib"
libaria2_assert_limited_aria2_exports "$INSTALL_DIR/lib/libaria2.0.dylib"

echo "SDK: $SDKROOT"
