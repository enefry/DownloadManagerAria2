#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/build-libaria2-apple-slice.sh <ios-arm64|ios-simulator-arm64>

Builds libaria2 as a dynamic library for one Apple mobile platform slice.
USAGE
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

SLICE="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/libaria2-build-common.sh"

ARIA2_DIR="$ROOT_DIR/third_party/aria2"
BUILD_DIR="$ROOT_DIR/build/libaria2-$SLICE"
INSTALL_DIR="$ROOT_DIR/artifacts/libaria2/$SLICE"
EXPORTS_FILE="$BUILD_DIR/libaria2.exports"

libaria2_ensure_upstream_source "$ROOT_DIR"

case "$SLICE" in
  ios-arm64)
    SDK_NAME="iphoneos"
    PLATFORM_NAME="ios"
    ARCH="arm64"
    MIN_VERSION="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
    MIN_FLAG="-miphoneos-version-min=$MIN_VERSION"
    TARGET_TRIPLE="arm64-apple-ios$MIN_VERSION"
    HOST="aarch64-apple-darwin"
    ;;
  ios-simulator-arm64)
    SDK_NAME="iphonesimulator"
    PLATFORM_NAME="ios-simulator"
    ARCH="arm64"
    MIN_VERSION="${IPHONESIMULATOR_DEPLOYMENT_TARGET:-15.0}"
    MIN_FLAG="-mios-simulator-version-min=$MIN_VERSION"
    TARGET_TRIPLE="arm64-apple-ios$MIN_VERSION-simulator"
    HOST="aarch64-apple-darwin"
    ;;
  *)
    usage
    exit 2
    ;;
esac

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "missing required file: $1" >&2
    exit 1
  fi
}

require_file "$ARIA2_DIR/configure.ac"

SDKROOT="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
PLATFORM_DIR="$(xcrun --sdk "$SDK_NAME" --show-sdk-platform-path)"
DEVELOPER_DIR="$(xcode-select -p)"
NCPU="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

rm -rf "$BUILD_DIR" "$INSTALL_DIR"
mkdir -p "$BUILD_DIR" "$INSTALL_DIR/include/aria2" "$INSTALL_DIR/lib"

pushd "$ARIA2_DIR" >/dev/null
if [[ ! -x ./configure ]]; then
  autoreconf -fi
fi
popd >/dev/null

export CC="$(xcrun --sdk "$SDK_NAME" -find clang)"
export CXX="$(xcrun --sdk "$SDK_NAME" -find clang++)"
export AR="$(xcrun --sdk "$SDK_NAME" -find ar)"
export RANLIB="$(xcrun --sdk "$SDK_NAME" -find ranlib)"
export STRIP="$(xcrun --sdk "$SDK_NAME" -find strip)"
export SDKROOT
export PKG_CONFIG="${PKG_CONFIG:-pkg-config}"
export PKG_CONFIG_PATH=
export PKG_CONFIG_LIBDIR=

COMMON_FLAGS="-target $TARGET_TRIPLE -arch $ARCH -isysroot $SDKROOT $MIN_FLAG"
COMMON_CPPFLAGS="-D__IPHONE_OS_VERSION_MIN_REQUIRED=150000"
COMMON_LDFLAGS="$COMMON_FLAGS -Wl,-platform_version,$PLATFORM_NAME,$MIN_VERSION,$(xcrun --sdk "$SDK_NAME" --show-sdk-version)"

export CFLAGS="${CFLAGS:-$COMMON_FLAGS}"
export CXXFLAGS="${CXXFLAGS:-$COMMON_FLAGS -std=c++11}"
export CPPFLAGS="${CPPFLAGS:-$COMMON_CPPFLAGS}"
export LDFLAGS="${LDFLAGS:-$COMMON_LDFLAGS}"

pushd "$BUILD_DIR" >/dev/null
"$ARIA2_DIR/configure" \
  --host="$HOST" \
  --target="$HOST" \
  --prefix="$INSTALL_DIR" \
  "${LIBARIA2_COMMON_CONFIGURE_ARGS[@]}" \
  ac_cv_func_fork=no \
  ac_cv_func_vfork=no \
  ac_cv_func_daemon=no \
  ac_cv_func_kqueue=no

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

libaria2_link_dylib_with_objc_wrapper \
  "$BUILD_DIR" \
  "$INSTALL_DIR/lib/libaria2.0.dylib" \
  "$WRAPPER_OBJECT" \
  "$CXX" \
  "$COMMON_LDFLAGS" \
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
echo "Platform: $PLATFORM_DIR"
echo "Developer: $DEVELOPER_DIR"
