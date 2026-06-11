#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/next-package-version.sh [explicit-version] [version-line] [initial-version] [branch-name]

Prints the next SwiftPM source package version.

Rules:
  - explicit-version wins and must be MAJOR.MINOR.PATCH
  - version-line "auto" on vMAJOR.MINOR_maint branches uses MAJOR.MINOR.x
  - version-line "auto" on main/master uses the newest existing semantic line
  - when no matching tags exist, initial-version is used
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

explicit_version="${1:-}"
version_line="${2:-auto}"
initial_version="${3:-1.0.0}"
branch_name="${4:-$(git rev-parse --abbrev-ref HEAD)}"

semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'
version_line_re='^[0-9]+\.[0-9]+$'
maint_branch_re='^v([0-9]+)\.([0-9]+)_maint$'

if [[ -n "$explicit_version" ]]; then
  if [[ ! "$explicit_version" =~ $semver_re ]]; then
    echo "explicit version must be MAJOR.MINOR.PATCH: $explicit_version" >&2
    exit 2
  fi
  if git rev-parse -q --verify "refs/tags/$explicit_version" >/dev/null; then
    echo "tag already exists: $explicit_version" >&2
    exit 1
  fi
  printf '%s\n' "$explicit_version"
  exit 0
fi

if [[ ! "$initial_version" =~ $semver_re ]]; then
  echo "initial version must be MAJOR.MINOR.PATCH: $initial_version" >&2
  exit 2
fi

versions=()
while IFS= read -r version; do
  versions+=("$version")
done < <(git tag --list --sort=v:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)

selected_line="$version_line"
if [[ "$selected_line" == "auto" || -z "$selected_line" ]]; then
  if [[ "$branch_name" =~ $maint_branch_re ]]; then
    selected_line="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  elif (( ${#versions[@]} > 0 )); then
    newest_index=$((${#versions[@]} - 1))
    newest="${versions[$newest_index]}"
    selected_line="${newest%.*}"
  else
    selected_line="${initial_version%.*}"
  fi
fi

if [[ ! "$selected_line" =~ $version_line_re ]]; then
  echo "version line must be MAJOR.MINOR or auto: $version_line" >&2
  exit 2
fi

latest_patch=""
for version in "${versions[@]}"; do
  if [[ "$version" == "$selected_line".* ]]; then
    latest_patch="${version##*.}"
  fi
done

if [[ -z "$latest_patch" ]]; then
  if [[ "$initial_version" == "$selected_line".* ]]; then
    next_version="$initial_version"
  else
    next_version="$selected_line.0"
  fi
else
  next_version="$selected_line.$((latest_patch + 1))"
fi

if git rev-parse -q --verify "refs/tags/$next_version" >/dev/null; then
  echo "tag already exists: $next_version" >&2
  exit 1
fi

printf '%s\n' "$next_version"
