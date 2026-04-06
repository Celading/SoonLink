#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/releases"
TARGET_TRIPLE=""
TARGET_DIR="$ROOT_DIR/target"
BIN_PATH=""
VERSION_OVERRIDE=""
ARCHIVE_PLATFORM=""
PACKAGE_PREFIX="soonlink-core"
PACKAGE_BIN_NAME="soonlnk"

usage() {
  cat <<'EOF'
Usage:
  build_release_bundle.sh \
    [--target <triple>] \
    [--target-dir <dir>] \
    [--bin <path>] \
    [--version <version>] \
    [--archive-platform <label>] \
    [--output-dir <dir>]
EOF
  exit 1
}

resolve_platform() {
  case "$1" in
    x86_64-unknown-linux-gnu) printf '%s\n' "linux-x86_64" ;;
    aarch64-unknown-linux-gnu) printf '%s\n' "linux-aarch64" ;;
    x86_64-apple-darwin) printf '%s\n' "darwin-x86_64" ;;
    aarch64-apple-darwin) printf '%s\n' "darwin-aarch64" ;;
    x86_64-w64-mingw32) printf '%s\n' "windows-x86_64" ;;
    *)
      os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
      arch_name="$(uname -m | tr '[:upper:]' '[:lower:]')"
      printf '%s-%s\n' "$os_name" "$arch_name"
      ;;
  esac
}

resolve_bin_name() {
  case "$1" in
    x86_64-w64-mingw32) printf '%s.exe\n' "$PACKAGE_BIN_NAME" ;;
    *) printf '%s\n' "$PACKAGE_BIN_NAME" ;;
  esac
}

native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -aw "$1"
  else
    printf '%s\n' "$1"
  fi
}

create_zip_archive() {
  archive_path="$1"
  stage_name="$2"
  dist_dir="$3"

  if command -v zip >/dev/null 2>&1; then
    (
      cd "$dist_dir"
      zip -qr "$archive_path" "$stage_name"
    )
    return 0
  fi

  if command -v powershell.exe >/dev/null 2>&1; then
    archive_native="$(native_path "$archive_path")"
    stage_native="$(native_path "$dist_dir/$stage_name")"
    powershell.exe -NoProfile -Command "Compress-Archive -Force -Path '$stage_native' -DestinationPath '$archive_native'"
    return 0
  fi

  echo "zip packaging requires zip or powershell.exe" >&2
  exit 1
}

copy_path() {
  relative_path="$1"
  source_path="$ROOT_DIR/$relative_path"
  target_path="$STAGE_DIR/$relative_path"

  [ -e "$source_path" ] || return 0

  mkdir -p "$(dirname "$target_path")"
  if [ -d "$source_path" ]; then
    cp -R "$source_path" "$target_path"
  else
    cp "$source_path" "$target_path"
  fi
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
    --bin)
      BIN_PATH="${2:-}"
      shift 2
      ;;
    --version)
      VERSION_OVERRIDE="${2:-}"
      shift 2
      ;;
    --archive-platform)
      ARCHIVE_PLATFORM="${2:-}"
      shift 2
      ;;
    --output-dir)
      DIST_DIR="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [ -z "$VERSION_OVERRIDE" ]; then
  VERSION_OVERRIDE="$(awk -F '"' '/^[[:space:]]*version[[:space:]]*=/{print $2; exit}' "$ROOT_DIR/cjpm.toml")"
fi

[ -n "$VERSION_OVERRIDE" ] || {
  echo "unable to resolve version from cjpm.toml" >&2
  exit 1
}

if [ -z "$ARCHIVE_PLATFORM" ]; then
  ARCHIVE_PLATFORM="$(resolve_platform "$TARGET_TRIPLE")"
fi

if [ -z "$BIN_PATH" ]; then
  PACKAGE_BIN_FILENAME="$(resolve_bin_name "$TARGET_TRIPLE")"
  for candidate in \
    "$TARGET_DIR/release/bin/main.exe" \
    "$TARGET_DIR/release/bin/main" \
    "$TARGET_DIR/$TARGET_TRIPLE/release/bin/main.exe" \
    "$TARGET_DIR/$TARGET_TRIPLE/release/bin/main" \
    "$ROOT_DIR/target/release/bin/main.exe" \
    "$ROOT_DIR/target/release/bin/main" \
    "$ROOT_DIR/target/$TARGET_TRIPLE/release/bin/main.exe" \
    "$ROOT_DIR/target/$TARGET_TRIPLE/release/bin/main" \
    "$ROOT_DIR/build/${PACKAGE_BIN_FILENAME}" \
    "$ROOT_DIR/build/$PACKAGE_BIN_NAME" \
    "$ROOT_DIR/${PACKAGE_BIN_FILENAME}" \
    "$ROOT_DIR/$PACKAGE_BIN_NAME"
  do
    if [ -f "$candidate" ]; then
      BIN_PATH="$candidate"
      break
    fi
  done
fi

[ -n "$BIN_PATH" ] && [ -f "$BIN_PATH" ] || {
  echo "no binary found; run cjpm build first or pass --bin <path>" >&2
  exit 1
}

mkdir -p "$DIST_DIR"

STAGE_NAME="${PACKAGE_PREFIX}-${VERSION_OVERRIDE}-${ARCHIVE_PLATFORM}"
STAGE_DIR="$DIST_DIR/$STAGE_NAME"
TARBALL_PATH="$DIST_DIR/${STAGE_NAME}.tar.gz"
ZIP_PATH="$DIST_DIR/${STAGE_NAME}.zip"
PACKAGE_BIN_FILENAME="$(resolve_bin_name "$TARGET_TRIPLE")"

rm -rf "$STAGE_DIR" "$TARBALL_PATH" "$ZIP_PATH"
mkdir -p "$STAGE_DIR"

cp "$BIN_PATH" "$STAGE_DIR/$PACKAGE_BIN_FILENAME"
chmod +x "$STAGE_DIR/$PACKAGE_BIN_FILENAME"

for public_path in \
  LICENSE \
  README.md \
  README-EN.MD \
  CHANGELOG.MD \
  CHANGELOG-EN.MD \
  .env.example \
  compose.yaml \
  compose.release.yaml \
  Dockerfile \
  config \
  web \
  docker/entrypoint.sh
do
  copy_path "$public_path"
done

tar -czf "$TARBALL_PATH" -C "$DIST_DIR" "$STAGE_NAME"
create_zip_archive "$ZIP_PATH" "$STAGE_NAME" "$DIST_DIR"
rm -rf "$STAGE_DIR"

echo "prepared release bundle: $TARBALL_PATH" >&2
echo "prepared release bundle: $ZIP_PATH" >&2
printf '%s\n' "$TARBALL_PATH"
printf '%s\n' "$ZIP_PATH"
