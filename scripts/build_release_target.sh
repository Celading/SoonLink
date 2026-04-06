#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TARGET_TRIPLE=""
TARGET_DIR="${ROOT_DIR}/target"
ARCHIVE_PLATFORM=""
VERSION_OVERRIDE=""

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

cjpm build --target "$TARGET_TRIPLE" --target-dir "$TARGET_DIR"

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

exec "$@"
