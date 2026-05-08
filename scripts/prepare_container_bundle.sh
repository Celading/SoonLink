#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BIN_PATH="${SOONLINK_BIN_PATH:-}"
ALLOW_NON_LINUX="${SOONLINK_ALLOW_NON_LINUX_BIN:-0}"

require_path() {
  if [ ! -e "$1" ]; then
    echo "missing required path: $1" >&2
    exit 1
  fi
}

copy_tree() {
  src_path="$1"
  dest_path="$2"
  rm -rf "$dest_path"
  mkdir -p "$(dirname "$dest_path")"
  cp -R "$src_path" "$dest_path"
}

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

require_path "$ROOT_DIR/config"
require_path "$ROOT_DIR/config/soonlink.toml"
require_path "$ROOT_DIR/web"
require_path "$ROOT_DIR/web/views/index.html"
require_path "$ROOT_DIR/web/static/js/main.js"
require_path "$ROOT_DIR/web/static/js/pwa.js"
require_path "$ROOT_DIR/web/static/manifest.webmanifest"
require_path "$ROOT_DIR/web/static/offline.html"
require_path "$ROOT_DIR/web/static/service-worker.js"
require_path "$ROOT_DIR/web/static/icons/app-icon.svg"
require_path "$ROOT_DIR/docker/entrypoint.sh"

mkdir -p "$DIST_DIR"
cp "$BIN_PATH" "$DIST_DIR/soonlnk"
chmod +x "$DIST_DIR/soonlnk"
copy_tree "$ROOT_DIR/config" "$DIST_DIR/config"
copy_tree "$ROOT_DIR/web" "$DIST_DIR/web"
mkdir -p "$DIST_DIR/docker"
cp "$ROOT_DIR/docker/entrypoint.sh" "$DIST_DIR/docker/entrypoint.sh"
chmod +x "$DIST_DIR/docker/entrypoint.sh"

require_path "$DIST_DIR/soonlnk"
require_path "$DIST_DIR/config/soonlink.toml"
require_path "$DIST_DIR/web/views/index.html"
require_path "$DIST_DIR/web/static/js/main.js"
require_path "$DIST_DIR/web/static/js/pwa.js"
require_path "$DIST_DIR/web/static/manifest.webmanifest"
require_path "$DIST_DIR/web/static/offline.html"
require_path "$DIST_DIR/web/static/service-worker.js"
require_path "$DIST_DIR/web/static/icons/app-icon.svg"
require_path "$DIST_DIR/docker/entrypoint.sh"

echo "prepared container bundle: $DIST_DIR"
