#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BIN_PATH="${SOONLINK_BIN_PATH:-}"
ALLOW_NON_LINUX="${SOONLINK_ALLOW_NON_LINUX_BIN:-0}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bin)
      BIN_PATH="${2:-}"
      shift 2
      ;;
    --allow-non-linux)
      ALLOW_NON_LINUX=1
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$BIN_PATH" ]; then
  for candidate in \
    "$ROOT_DIR/target/release/bin/main" \
    "$ROOT_DIR/build/soonlnk" \
    "$ROOT_DIR/soonlnk"
  do
    if [ -f "$candidate" ]; then
      BIN_PATH="$candidate"
      break
    fi
  done
fi

if [ -z "$BIN_PATH" ] || [ ! -f "$BIN_PATH" ]; then
  echo "no binary found; run cjpm build first or pass --bin <path>" >&2
  exit 1
fi

if command -v file >/dev/null 2>&1; then
  FILE_INFO="$(file "$BIN_PATH")"
  echo "$FILE_INFO"
  case "$FILE_INFO" in
    *ELF*)
      ;;
    *)
      if [ "$ALLOW_NON_LINUX" != "1" ]; then
        echo "expected a Linux ELF binary for Docker packaging; set SOONLINK_ALLOW_NON_LINUX_BIN=1 to override" >&2
        exit 1
      fi
      ;;
  esac
fi

mkdir -p "$DIST_DIR"
cp "$BIN_PATH" "$DIST_DIR/soonlnk"
chmod +x "$DIST_DIR/soonlnk"

echo "prepared container bundle: $DIST_DIR/soonlnk"
