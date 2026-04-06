#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SDK_URL=""
SDK_DIR="${ROOT_DIR}/.ci/cangjie"
STDX_DIR="${ROOT_DIR}/.ci/cangjie_stdx"
STDX_REPO="${CANGJIE_STDX_REPO:-https://gitcode.com/Cangjie/cangjie_stdx}"
STDX_REF="${CANGJIE_STDX_GIT_REF:-v1.1.0-beta.25}"
FORCE_STDX_BUILD=0

usage() {
  cat <<'EOF'
Usage:
  install_cangjie_ci.sh \
    --sdk-url <url> \
    [--sdk-dir <dir>] \
    [--stdx-dir <dir>] \
    [--stdx-repo <url>] \
    [--stdx-ref <git-ref>] \
    [--force-stdx-build]
EOF
  exit 1
}

cangjie_driver() {
  if [ -x "$SDK_DIR/bin/cjc" ]; then
    printf '%s\n' "$SDK_DIR/bin/cjc"
    return 0
  fi
  if [ -x "$SDK_DIR/bin/cjc.exe" ]; then
    printf '%s\n' "$SDK_DIR/bin/cjc.exe"
    return 0
  fi
  return 1
}

native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -aw "$1"
  else
    printf '%s\n' "$1"
  fi
}

extract_archive() {
  archive_path="$1"
  dest_dir="$2"

  if tar -xf "$archive_path" -C "$dest_dir" >/dev/null 2>&1; then
    return 0
  fi

  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$archive_path" -d "$dest_dir"
    return 0
  fi

  if command -v powershell.exe >/dev/null 2>&1; then
    archive_native="$(native_path "$archive_path")"
    dest_native="$(native_path "$dest_dir")"
    powershell.exe -NoProfile -Command "Expand-Archive -Force -Path '$archive_native' -DestinationPath '$dest_native'"
    return 0
  fi

  echo "unable to extract archive: $archive_path" >&2
  exit 1
}

sedi() {
  expr="$1"
  file="$2"
  if sed --version >/dev/null 2>&1; then
    sed -i "$expr" "$file"
  else
    sed -i '' "$expr" "$file"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sdk-url)
      SDK_URL="${2:-}"
      shift 2
      ;;
    --sdk-dir)
      SDK_DIR="${2:-}"
      shift 2
      ;;
    --stdx-dir)
      STDX_DIR="${2:-}"
      shift 2
      ;;
    --stdx-repo)
      STDX_REPO="${2:-}"
      shift 2
      ;;
    --stdx-ref)
      STDX_REF="${2:-}"
      shift 2
      ;;
    --force-stdx-build)
      FORCE_STDX_BUILD=1
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      ;;
  esac
done

[ -n "$SDK_URL" ] || usage

SDK_PARENT="$(dirname "$SDK_DIR")"
STDX_PARENT="$(dirname "$STDX_DIR")"
SDK_ARCHIVE="${SDK_PARENT}/cangjie-sdk.tar.gz"
SDK_STAGE="${SDK_PARENT}/cangjie-sdk.unpack"

mkdir -p "$SDK_PARENT" "$STDX_PARENT"

if ! cangjie_driver >/dev/null 2>&1; then
  rm -rf "$SDK_DIR" "$SDK_STAGE"
  mkdir -p "$SDK_STAGE"
  curl -L --fail "$SDK_URL" -o "$SDK_ARCHIVE"
  extract_archive "$SDK_ARCHIVE" "$SDK_STAGE"
  first_entry="$(find "$SDK_STAGE" -mindepth 1 -maxdepth 1 | head -n 1)"
  [ -n "$first_entry" ] || {
    echo "failed to unpack Cangjie SDK from $SDK_URL" >&2
    exit 1
  }
  if [ -d "$first_entry" ] && [ "$(find "$SDK_STAGE" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = "1" ]; then
    mv "$first_entry" "$SDK_DIR"
  else
    mkdir -p "$SDK_DIR"
    cp -R "$SDK_STAGE"/. "$SDK_DIR"/
  fi
  rm -rf "$SDK_STAGE" "$SDK_ARCHIVE"
fi

export CANGJIE_HOME="$SDK_DIR"
export PATH="$CANGJIE_HOME/bin:$CANGJIE_HOME/tools/bin:$PATH"

if [ ! -d "$STDX_DIR/.git" ]; then
  rm -rf "$STDX_DIR"
  git clone --depth 1 --branch "$STDX_REF" "$STDX_REPO" "$STDX_DIR"
fi

if [ -f "$STDX_DIR/src/stdx/dynamicLoader/opensslSymbols.c" ]; then
  sedi 's/if (&dlopen == NULL)/if (0)/' "$STDX_DIR/src/stdx/dynamicLoader/opensslSymbols.c"
  sedi 's/if (&dlsym == NULL)/if (0)/' "$STDX_DIR/src/stdx/dynamicLoader/opensslSymbols.c"
  sedi 's/if (&dlclose != NULL && g_singletonHandle != NULL)/if (g_singletonHandle != NULL)/' "$STDX_DIR/src/stdx/dynamicLoader/opensslSymbols.c"
  sedi 's/if (&dlclose != NULL && g_singletonHandleSsl != NULL && g_singletonHandleSsl != g_singletonHandle)/if (g_singletonHandleSsl != NULL \&\& g_singletonHandleSsl != g_singletonHandle)/' "$STDX_DIR/src/stdx/dynamicLoader/opensslSymbols.c"
fi

if [ "$FORCE_STDX_BUILD" = "1" ] || [ ! -d "$STDX_DIR/target" ]; then
  (
    cd "$STDX_DIR"
    cjpm build
  )
fi

export CANGJIE_STDX_PATH="$STDX_DIR/target"

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "CANGJIE_HOME=$CANGJIE_HOME"
    echo "CANGJIE_STDX_PATH=$CANGJIE_STDX_PATH"
  } >> "$GITHUB_ENV"
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  {
    echo "$CANGJIE_HOME/bin"
    echo "$CANGJIE_HOME/tools/bin"
  } >> "$GITHUB_PATH"
fi

printf '%s\n' "$CANGJIE_HOME"
