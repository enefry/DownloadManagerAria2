#!/usr/bin/env bash

LIBARIA2_UPSTREAM_REPOSITORY="${LIBARIA2_UPSTREAM_REPOSITORY:-https://github.com/aria2/aria2.git}"
LIBARIA2_UPSTREAM_REF="${LIBARIA2_UPSTREAM_REF:-release-1.37.0}"

LIBARIA2_COMMON_CONFIGURE_ARGS=(
  --enable-libaria2
  --enable-shared
  --disable-static
  --disable-dependency-tracking
  --disable-metalink
  --disable-xml-rpc
  --disable-websocket
  --disable-epoll
  --with-appletls
  --without-gnutls
  --without-libnettle
  --without-libgcrypt
  --without-libgmp
  --without-openssl
  --without-libssh2
  --without-libcares
  --without-libz
  --without-sqlite3
  --without-libxml2
  --without-libexpat
  lt_cv_sys_max_cmd_len=262144
)

LIBARIA2_PUBLIC_DEMANGLED_SYMBOL_RE='^aria2::(libraryInit\(\)|libraryDeinit\(\)|SessionConfig::SessionConfig\(\)|sessionNew\(.*|sessionFinal\(aria2::Session\*\)|run\(aria2::Session\*, aria2::RUN_MODE\)|gidToHex\(unsigned long long\)|hexToGid\(.*|isNull\(unsigned long long\)|addUri\(aria2::Session\*, .*|addMetalink\(aria2::Session\*, .*|addTorrent\(aria2::Session\*, .*|getActiveDownload\(aria2::Session\*\)|removeDownload\(aria2::Session\*, unsigned long long, bool\)|pauseDownload\(aria2::Session\*, unsigned long long, bool\)|unpauseDownload\(aria2::Session\*, unsigned long long\)|changeOption\(aria2::Session\*, unsigned long long, .*|getGlobalOption\(aria2::Session\*, .*|getGlobalOptions\(aria2::Session\*\)|changeGlobalOption\(aria2::Session\*, .*|getGlobalStat\(aria2::Session\*\)|changePosition\(aria2::Session\*, unsigned long long, int, aria2::OffsetMode\)|shutdown\(aria2::Session\*, bool\)|getDownloadHandle\(aria2::Session\*, unsigned long long\)|deleteDownloadHandle\(aria2::DownloadHandle\*\))$'
LIBARIA2_THIRD_PARTY_SYMBOL_RE='^(_SSL_|_OPENSSL_|_libssh2|_ares_|_sqlite3_|_zlib|_xml|_XML_|_gcry_|_gmp|_nettle)'
LIBARIA2_OBJC_EXPORT_SYMBOLS=(
  _DMAria2ErrorDomain
  _DMAria2GIDKey
  _DMAria2StatusKey
  _DMAria2TotalLengthKey
  _DMAria2CompletedLengthKey
  _DMAria2DownloadSpeedKey
  _DMAria2UploadSpeedKey
  _DMAria2ErrorCodeKey
  _DMAria2FilesKey
  _DMAria2Version
  '_OBJC_CLASS_$_DMAria2Session'
  '_OBJC_METACLASS_$_DMAria2Session'
)

libaria2_ensure_upstream_source() {
  local root_dir="$1"
  local aria2_dir="$root_dir/third_party/aria2"
  local patch

  if [[ -f "$aria2_dir/configure.ac" ]]; then
    :
  else
    mkdir -p "$(dirname "$aria2_dir")"
    echo "Fetching aria2 source $LIBARIA2_UPSTREAM_REF from $LIBARIA2_UPSTREAM_REPOSITORY"
    git clone --depth 1 --branch "$LIBARIA2_UPSTREAM_REF" "$LIBARIA2_UPSTREAM_REPOSITORY" "$aria2_dir"
  fi

  for patch in "$root_dir"/patches/aria2/*.patch; do
    [[ -e "$patch" ]] || continue
    if git -C "$aria2_dir" apply --reverse --check "$patch" >/dev/null 2>&1; then
      echo "aria2 patch already applied: $(basename "$patch")"
    elif git -C "$aria2_dir" apply --check "$patch" >/dev/null 2>&1; then
      echo "Applying aria2 patch: $(basename "$patch")"
      git -C "$aria2_dir" apply "$patch"
    else
      echo "failed to apply aria2 patch: $patch" >&2
      git -C "$aria2_dir" apply --check "$patch"
      return 1
    fi
  done
}

libaria2_generate_exports_file() {
  local dylib="$1"
  local exports_file="$2"
  local symbol
  local demangled

  {
    while IFS= read -r symbol; do
      demangled="$(c++filt <<<"$symbol")"
      if [[ "$demangled" =~ $LIBARIA2_PUBLIC_DEMANGLED_SYMBOL_RE ]]; then
        printf '%s\n' "$symbol"
      fi
    done < <(nm -gU "$dylib" | awk '{print $3}')
    printf '%s\n' "${LIBARIA2_OBJC_EXPORT_SYMBOLS[@]}"
  } | sort -u > "$exports_file"
}

libaria2_compile_objc_wrapper() {
  local root_dir="$1"
  local aria2_dir="$2"
  local build_dir="$3"
  local compiler="$4"
  local compile_flags="$5"
  local wrapper_build_dir="$build_dir/objc-wrapper"
  local wrapper_object="$wrapper_build_dir/DMAria2.o"

  mkdir -p "$wrapper_build_dir"
  "$compiler" $compile_flags \
    -std=c++11 \
    -fobjc-arc \
    -fblocks \
    -I"$root_dir/Sources/ObjCWrapper" \
    -I"$aria2_dir/src/includes" \
    -c "$root_dir/Sources/ObjCWrapper/DMAria2.mm" \
    -o "$wrapper_object"

  printf '%s\n' "$wrapper_object"
}

libaria2_link_dylib_with_objc_wrapper() {
  local build_dir="$1"
  local output_dylib="$2"
  local wrapper_object="$3"
  local compiler="$4"
  local link_flags="$5"
  local exports_file="$6"
  local -a objects

  while IFS= read -r -d '' object; do
    objects+=("$object")
  done < <(find "$build_dir/src/.libs" -maxdepth 1 -name '*.o' -print0 | sort -z)

  "$compiler" $link_flags \
    -dynamiclib \
    -install_name "@rpath/libaria2.0.dylib" \
    -compatibility_version 1.0.0 \
    -current_version 1.0.0 \
    -Wl,-exported_symbols_list,"$exports_file" \
    -o "$output_dylib" \
    "${objects[@]}" \
    "$wrapper_object" \
    -framework Foundation \
    -framework CoreFoundation \
    -framework Security \
    -lc++
}

libaria2_install_public_headers() {
  local root_dir="$1"
  local aria2_dir="$2"
  local install_dir="$3"

  mkdir -p "$install_dir/include/aria2"
  install -m 644 "$aria2_dir/src/includes/aria2/aria2.h" "$install_dir/include/aria2/aria2.h"
  install -m 644 "$root_dir/Sources/ObjCWrapper/DMAria2.h" "$install_dir/include/DMAria2.h"
  install -m 644 "$root_dir/Sources/ObjCWrapper/module.modulemap" "$install_dir/include/module.modulemap"
}

libaria2_third_party_symbol_count() {
  local dylib="$1"

  nm -gU "$dylib" \
    | awk '{print $3}' \
    | grep -E "$LIBARIA2_THIRD_PARTY_SYMBOL_RE" \
    | wc -l \
    || true
}

libaria2_assert_no_third_party_exports() {
  local dylib="$1"
  local count

  count="$(libaria2_third_party_symbol_count "$dylib")"
  count="${count//[[:space:]]/}"
  echo "Third-party exported symbol count: $count"

  if [[ "$count" != "0" ]]; then
    echo "third-party symbols are still exported: $dylib" >&2
    return 1
  fi
}

libaria2_assert_system_dynamic_dependencies() {
  local dylib="$1"
  local bad_deps

  bad_deps="$(
    otool -L "$dylib" \
      | awk 'NR > 1 {print $1}' \
      | grep -Ev '^(@rpath/libaria2\.0\.dylib|/usr/lib/|/System/Library/)' \
      || true
  )"

  if [[ -n "$bad_deps" ]]; then
    echo "non-system dynamic dependencies found in $dylib:" >&2
    echo "$bad_deps" >&2
    return 1
  fi
}

libaria2_assert_objc_exports() {
  local dylib="$1"
  local symbols

  symbols="$(nm -gU "$dylib" | awk '{print $3}')"
  for symbol in "${LIBARIA2_OBJC_EXPORT_SYMBOLS[@]}"; do
    if ! grep -Fxq "$symbol" <<<"$symbols"; then
      echo "missing ObjC wrapper export $symbol in $dylib" >&2
      return 1
    fi
  done
}

libaria2_assert_limited_aria2_exports() {
  local dylib="$1"
  local symbol
  local demangled
  local unexpected=()

  while IFS= read -r symbol; do
    demangled="$(c++filt <<<"$symbol")"
    if [[ "$demangled" == aria2::* && ! "$demangled" =~ $LIBARIA2_PUBLIC_DEMANGLED_SYMBOL_RE ]]; then
      unexpected+=("$demangled")
    fi
  done < <(nm -gU "$dylib" | awk '{print $3}')

  if (( ${#unexpected[@]} > 0 )); then
    echo "unexpected aria2 internal exports in $dylib:" >&2
    printf '%s\n' "${unexpected[@]:0:20}" >&2
    return 1
  fi
}
