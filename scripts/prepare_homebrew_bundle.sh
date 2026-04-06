#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/homebrew"
BIN_PATH="${SOONLINK_BIN_PATH:-}"
ALLOW_NON_DARWIN="${SOONLINK_ALLOW_NON_DARWIN_BIN:-0}"
VERSION_OVERRIDE="${SOONLINK_VERSION:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bin)
      BIN_PATH="${2:-}"
      shift 2
      ;;
    --version)
      VERSION_OVERRIDE="${2:-}"
      shift 2
      ;;
    --allow-non-darwin)
      ALLOW_NON_DARWIN=1
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

if [ -n "$VERSION_OVERRIDE" ]; then
  VERSION="$VERSION_OVERRIDE"
else
  VERSION="$(awk -F '"' '/^[[:space:]]*version[[:space:]]*=/{print $2; exit}' "$ROOT_DIR/cjpm.toml")"
fi

if [ -z "$VERSION" ]; then
  echo "unable to resolve version from cjpm.toml" >&2
  exit 1
fi

if command -v file >/dev/null 2>&1; then
  FILE_INFO="$(file "$BIN_PATH")"
  echo "$FILE_INFO"
  case "$FILE_INFO" in
    *Mach-O*)
      ;;
    *)
      if [ "$ALLOW_NON_DARWIN" != "1" ]; then
        echo "expected a macOS Mach-O binary for Homebrew packaging; set SOONLINK_ALLOW_NON_DARWIN_BIN=1 to override" >&2
        exit 1
      fi
      ;;
  esac
fi

OS_NAME="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH_NAME="$(uname -m | tr '[:upper:]' '[:lower:]')"
case "$ARCH_NAME" in
  arm64) ARCH_NAME="aarch64" ;;
  amd64) ARCH_NAME="x86_64" ;;
esac
PLATFORM="${OS_NAME}-${ARCH_NAME}"
STAGE_NAME="soonlink-core-${VERSION}-${PLATFORM}"
STAGE_DIR="$DIST_DIR/$STAGE_NAME"
TARBALL_PATH="$DIST_DIR/${STAGE_NAME}.tar.gz"

rm -rf "$STAGE_DIR" "$TARBALL_PATH"
mkdir -p "$STAGE_DIR"

cp "$BIN_PATH" "$STAGE_DIR/soonlnk"
chmod +x "$STAGE_DIR/soonlnk"
cp -R "$ROOT_DIR/config" "$STAGE_DIR/config"
cp -R "$ROOT_DIR/web" "$STAGE_DIR/web"
cp "$ROOT_DIR/README.md" "$STAGE_DIR/README.md"
cp "$ROOT_DIR/README-EN.MD" "$STAGE_DIR/README-EN.MD"
cp "$ROOT_DIR/LICENSE" "$STAGE_DIR/LICENSE"
cp "$ROOT_DIR/CHANGELOG.MD" "$STAGE_DIR/CHANGELOG.MD"
cp "$ROOT_DIR/.env.example" "$STAGE_DIR/.env.example"
cp "$ROOT_DIR/compose.release.yaml" "$STAGE_DIR/compose.release.yaml"

mkdir -p "$DIST_DIR"
tar -czf "$TARBALL_PATH" -C "$DIST_DIR" "$STAGE_NAME"

echo "prepared homebrew bundle: $TARBALL_PATH"
