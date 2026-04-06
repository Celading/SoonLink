#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TARGET_TRIPLE=""
TARGET_DIR="${ROOT_DIR}/target"
ARCHIVE_PLATFORM=""
VERSION_OVERRIDE=""

escape_github_annotation() {
  printf '%s' "$1" | sed 's/%/%25/g; s/\r/%0D/g; s/\n/%0A/g'
}

annotate_github_error() {
  [ -n "${GITHUB_ACTIONS:-}" ] || return 0
  message="$(escape_github_annotation "$1")"
  printf '::error::%s\n' "$message" >&2
}

find_sdk_executable() {
  sdk_root="$1"
  shift

  while [ "$#" -gt 0 ]; do
    candidate="$(find "$sdk_root" -type f -name "$1" 2>/dev/null | head -n 1 || true)"
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    shift
  done

  return 1
}

cjpm_command() {
  if command -v cjpm >/dev/null 2>&1; then
    command -v cjpm
    return 0
  fi

  if [ -n "${CANGJIE_HOME:-}" ] && [ -d "${CANGJIE_HOME}" ]; then
    find_sdk_executable "$CANGJIE_HOME" cjpm cjpm.exe
    return 0
  fi

  return 1
}

require_command_success() {
  label="$1"
  shift
  log_file="$(mktemp "${TMPDIR:-/tmp}/soonlink-release-build-XXXXXX.log")"

  if "$@" >"$log_file" 2>&1; then
    rm -f "$log_file"
    return 0
  fi

  summary="$(tail -n 20 "$log_file" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
  [ -n "$summary" ] || summary="no stderr captured"
  annotate_github_error "$label failed: $summary"
  cat "$log_file" >&2
  rm -f "$log_file"
  return 1
}

usage() {
  cat <<'EOF'
Usage:
  build_release_target.sh \
    --target <triple> \
    [--target-dir <dir>] \
    [--archive-platform <label>] \
    [--version <version>]
EOF
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      TARGET_TRIPLE="${2:-}"
      shift 2
      ;;
    --target-dir)
      TARGET_DIR="${2:-}"
      shift 2
      ;;
    --archive-platform)
      ARCHIVE_PLATFORM="${2:-}"
      shift 2
      ;;
    --version)
      VERSION_OVERRIDE="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      ;;
  esac
done

[ -n "$TARGET_TRIPLE" ] || usage

mkdir -p "$TARGET_DIR"
cd "$ROOT_DIR"

CJPM_BIN="$(cjpm_command || true)"
[ -n "$CJPM_BIN" ] || {
  annotate_github_error "cjpm is unavailable for ${TARGET_TRIPLE}; ensure install_cangjie_ci.sh completed successfully"
  echo "cjpm is unavailable for ${TARGET_TRIPLE}; ensure install_cangjie_ci.sh completed successfully" >&2
  exit 1
}

require_command_success "cjpm build for ${TARGET_TRIPLE}" \
  "$CJPM_BIN" build --target "$TARGET_TRIPLE" --target-dir "$TARGET_DIR"

set -- \
  "$ROOT_DIR/scripts/build_release_bundle.sh" \
  --target "$TARGET_TRIPLE" \
  --target-dir "$TARGET_DIR"

if [ -n "$ARCHIVE_PLATFORM" ]; then
  set -- "$@" --archive-platform "$ARCHIVE_PLATFORM"
fi

if [ -n "$VERSION_OVERRIDE" ]; then
  set -- "$@" --version "$VERSION_OVERRIDE"
fi

bundle_log="$(mktemp "${TMPDIR:-/tmp}/soonlink-release-bundle-XXXXXX.log")"
if ! bundle_stdout="$("$@" 2>"$bundle_log")"; then
  summary="$(tail -n 20 "$bundle_log" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
  [ -n "$summary" ] || summary="no stderr captured"
  annotate_github_error "release bundle packaging for ${TARGET_TRIPLE} failed: ${summary}"
  cat "$bundle_log" >&2
  rm -f "$bundle_log"
  exit 1
fi

rm -f "$bundle_log"
printf '%s\n' "$bundle_stdout"
