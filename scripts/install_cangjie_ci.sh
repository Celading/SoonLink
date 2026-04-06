#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SDK_URL=""
SDK_DIR="${ROOT_DIR}/.ci/cangjie"
STDX_DIR="${ROOT_DIR}/.ci/cangjie_stdx"
STDX_REPO="${CANGJIE_STDX_REPO:-https://gitcode.com/Cangjie/cangjie_stdx}"
STDX_REF="${CANGJIE_STDX_GIT_REF:-v1.1.0-beta.25}"
FORCE_STDX_BUILD=0

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

find_sdk_directory() {
  sdk_root="$1"
  shift

  while [ "$#" -gt 0 ]; do
    candidate="$(find "$sdk_root" -type d -path "$1" 2>/dev/null | head -n 1 || true)"
    if [ -n "$candidate" ] && [ -d "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    shift
  done

  return 1
}

escape_github_annotation() {
  printf '%s' "$1" | sed 's/%/%25/g; s/\r/%0D/g; s/\n/%0A/g'
}

annotate_github_error() {
  [ -n "${GITHUB_ACTIONS:-}" ] || return 0
  message="$(escape_github_annotation "$1")"
  printf '::error::%s\n' "$message"
}

join_path_entries() {
  joined=""

  while [ "$#" -gt 0 ]; do
    if [ -n "$1" ]; then
      if [ -n "$joined" ]; then
        joined="${joined}:$1"
      else
        joined="$1"
      fi
    fi
    shift
  done

  printf '%s\n' "$joined"
}

require_command_success() {
  log_file="$(mktemp "${TMPDIR:-/tmp}/soonlink-ci-command-XXXXXX.log")"
  label="$1"
  shift

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
  find_sdk_executable "$SDK_DIR" cjc cjc.exe
}

cjpm_driver() {
  find_sdk_executable "$SDK_DIR" cjpm cjpm.exe
}

runtime_library_dir() {
  runtime_lib="$(find "$SDK_DIR" -type f \( -name 'libcangjie-runtime.so' -o -name 'libcangjie-runtime.dylib' \) 2>/dev/null | head -n 1 || true)"
  if [ -n "$runtime_lib" ]; then
    dirname "$runtime_lib"
    return 0
  fi

  find_sdk_directory "$SDK_DIR" '*/runtime/lib/*'
}

tools_library_dir() {
  find_sdk_directory "$SDK_DIR" '*/tools/lib'
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

CANGJIE_BIN="$(cangjie_driver || true)"
[ -n "$CANGJIE_BIN" ] || {
  echo "failed to locate cjc inside $SDK_DIR after SDK extraction" >&2
  exit 1
}

CJPM_BIN="$(cjpm_driver || true)"
[ -n "$CJPM_BIN" ] || {
  echo "failed to locate cjpm inside $SDK_DIR after SDK extraction" >&2
  exit 1
}

CANGJIE_BIN_DIR="$(dirname "$CANGJIE_BIN")"
CANGJIE_TOOLS_DIR="$(dirname "$CJPM_BIN")"
export PATH="$CANGJIE_BIN_DIR:$CANGJIE_TOOLS_DIR:$PATH"

RUNTIME_LIB_DIR="$(runtime_library_dir || true)"
TOOLS_LIB_DIR="$(tools_library_dir || true)"
case "$(uname -s)" in
  Linux)
    if [ -n "$RUNTIME_LIB_DIR" ] || [ -n "$TOOLS_LIB_DIR" ]; then
      export LD_LIBRARY_PATH="$(join_path_entries "$RUNTIME_LIB_DIR" "$TOOLS_LIB_DIR" "${LD_LIBRARY_PATH:-}")"
    fi
    ;;
  Darwin)
    if [ -n "$RUNTIME_LIB_DIR" ] || [ -n "$TOOLS_LIB_DIR" ]; then
      export DYLD_LIBRARY_PATH="$(join_path_entries "$RUNTIME_LIB_DIR" "$TOOLS_LIB_DIR" "${DYLD_LIBRARY_PATH:-}")"
    fi
    ;;
esac

command -v cjc >/dev/null 2>&1 || {
  echo "cjc is still unavailable after SDK setup" >&2
  exit 1
}

command -v cjpm >/dev/null 2>&1 || {
  echo "cjpm is still unavailable after SDK setup" >&2
  exit 1
}

require_command_success "cjc -v" "$CANGJIE_BIN" -v
require_command_success "cjpm --version" "$CJPM_BIN" --version

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
    require_command_success "stdx cjpm build" "$CJPM_BIN" build
  )
fi

export CANGJIE_STDX_PATH="$STDX_DIR/target"

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "CANGJIE_HOME=$CANGJIE_HOME"
    echo "CANGJIE_STDX_PATH=$CANGJIE_STDX_PATH"
    if [ -n "${LD_LIBRARY_PATH:-}" ]; then
      echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
    fi
    if [ -n "${DYLD_LIBRARY_PATH:-}" ]; then
      echo "DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH"
    fi
  } >> "$GITHUB_ENV"
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  {
    echo "$CANGJIE_BIN_DIR"
    echo "$CANGJIE_TOOLS_DIR"
  } >> "$GITHUB_PATH"
fi

printf '%s\n' "$CANGJIE_HOME"
