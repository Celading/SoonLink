#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SDK_URL=""
SDK_DIR="${ROOT_DIR}/.ci/cangjie"
DEVECO_SDK_URL=""
DEVECO_DIR="${ROOT_DIR}/.ci/deveco_cangjie"
STDX_DIR="${ROOT_DIR}/.ci/cangjie_stdx"
STDX_REPO="${CANGJIE_STDX_REPO:-https://gitcode.com/Cangjie/cangjie_stdx}"
STDX_REF="${CANGJIE_STDX_GIT_REF:-v1.1.0-beta.25}"
STDX_RELEASE_VERSION="${CANGJIE_STDX_RELEASE_VERSION:-}"
STDX_TARGETS=""
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
    [--deveco-sdk-url <url>] \
    [--deveco-dir <dir>] \
    [--stdx-dir <dir>] \
    [--stdx-repo <url>] \
    [--stdx-ref <git-ref>] \
    [--stdx-release-version <version>] \
    [--stdx-target <triple>] \
    [--force-stdx-build]
EOF
  exit 1
}

append_stdx_target() {
  target_triple="$1"
  case " $STDX_TARGETS " in
    *" $target_triple "*) return 0 ;;
  esac

  if [ -n "$STDX_TARGETS" ]; then
    STDX_TARGETS="${STDX_TARGETS} ${target_triple}"
  else
    STDX_TARGETS="$target_triple"
  fi
}

cangjie_driver() {
  find_sdk_executable "$SDK_DIR" cjc cjc.exe
}

cjpm_driver() {
  find_sdk_executable "$SDK_DIR" cjpm cjpm.exe
}

runtime_library_dir() {
  runtime_lib="$(find "$SDK_DIR" -type f \( -name 'libcangjie-runtime.so' -o -name 'libcangjie-runtime.dylib' -o -name 'libcangjie-runtime.dll' \) 2>/dev/null | head -n 1 || true)"
  if [ -n "$runtime_lib" ]; then
    dirname "$runtime_lib"
    return 0
  fi

  find_sdk_directory "$SDK_DIR" '*/runtime/lib/*' '*/runtime/bin/*' '*/lib/*'
}

tools_library_dir() {
  find_sdk_directory "$SDK_DIR" '*/tools/lib'
}

resolve_stdx_root_from_output() {
  output_dir="$1"
  [ -d "$output_dir" ] || return 1

  match_dir="$(find "$output_dir" -type d -path '*/static/stdx' 2>/dev/null | head -n 1 || true)"
  if [ -n "$match_dir" ]; then
    dirname "$(dirname "$(dirname "$match_dir")")"
    return 0
  fi

  return 1
}

search_stdx_root() {
  search_root="$1"
  [ -d "$search_root" ] || return 1

  match_dir="$(find "$search_root" -type d -path '*/static/stdx' 2>/dev/null | head -n 1 || true)"
  if [ -n "$match_dir" ]; then
    dirname "$(dirname "$(dirname "$match_dir")")"
    return 0
  fi

  return 1
}

resolve_stdx_root() {
  candidate_root="$(resolve_stdx_root_from_output "$STDX_DIR/target" || true)"
  if [ -n "$candidate_root" ]; then
    printf '%s\n' "$candidate_root"
    return 0
  fi

  for candidate in \
    "$(dirname "$CANGJIE_HOME")/stdx_Build" \
    "$CANGJIE_HOME/../stdx_Build" \
    "$(dirname "$STDX_DIR")/stdx_Build"
  do
    candidate_root="$(resolve_stdx_root_from_output "$candidate" || true)"
    if [ -n "$candidate_root" ]; then
      printf '%s\n' "$candidate_root"
      return 0
    fi
  done

  for search_root in \
    "${RUNNER_TEMP:-}" \
    "$(dirname "$CANGJIE_HOME")" \
    "$STDX_PARENT" \
    "${HOME:-}" \
    "${HOME:-}/.cangjie"
  do
    candidate_root="$(search_stdx_root "$search_root" || true)"
    if [ -n "$candidate_root" ]; then
      printf '%s\n' "$candidate_root"
      return 0
    fi
  done

  return 1
}

find_stdx_alias_source() {
  stdx_root="$1"
  alias_name="$2"

  case "$alias_name" in
    linux_x86_64_llvm)
      find "$stdx_root" -mindepth 1 -maxdepth 1 -type d \
        \( -name '*linux*x86_64*llvm*' -o -name '*linux*x86_64*cjnative*' \) \
        2>/dev/null | head -n 1
      ;;
    linux_aarch64_llvm)
      find "$stdx_root" -mindepth 1 -maxdepth 1 -type d \
        \( -name '*linux*aarch64*llvm*' -o -name '*linux*aarch64*cjnative*' \) \
        2>/dev/null | head -n 1
      ;;
    cj_stdx_darwin_x86_64_llvm)
      find "$stdx_root" -mindepth 1 -maxdepth 1 -type d \
        \( -name '*darwin*x86_64*llvm*' -o -name '*macos*x86_64*llvm*' \) \
        2>/dev/null | head -n 1
      ;;
    cj_stdx_darwin_aarch64_llvm)
      find "$stdx_root" -mindepth 1 -maxdepth 1 -type d \
        \( -name '*darwin*aarch64*llvm*' -o -name '*macos*aarch64*llvm*' -o -name '*darwin*arm64*llvm*' \) \
        2>/dev/null | head -n 1
      ;;
    windows_x86_64_cjnative)
      find "$stdx_root" -mindepth 1 -maxdepth 1 -type d \
        \( -name 'windows_x86_64_cjnative' -o -name '*windows*x86_64*cjnative*' -o -name '*x86_64*w64*mingw32*' \) \
        2>/dev/null | head -n 1
      ;;
    linux_ohos_aarch64_cjnative)
      find "$stdx_root" -mindepth 1 -maxdepth 1 -type d \
        \( -name 'linux_ohos_aarch64_cjnative' -o -name '*linux*ohos*aarch64*cjnative*' -o -name '*ohos*aarch64*llvm*' \) \
        2>/dev/null | head -n 1
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_stdx_alias() {
  stdx_root="$1"
  alias_name="$2"

  [ -d "$stdx_root/$alias_name/static/stdx" ] && return 0
  alias_source="$(find_stdx_alias_source "$stdx_root" "$alias_name" || true)"
  [ -n "$alias_source" ] || return 0
  [ -d "$alias_source/static/stdx" ] || return 0

  link_or_copy_alias "$alias_source" "$stdx_root/$alias_name"
}

stdx_alias_name_for_target() {
  case "$1" in
    x86_64-unknown-linux-gnu) printf '%s\n' "linux_x86_64_llvm" ;;
    aarch64-unknown-linux-gnu) printf '%s\n' "linux_aarch64_llvm" ;;
    x86_64-apple-darwin) printf '%s\n' "cj_stdx_darwin_x86_64_llvm" ;;
    aarch64-apple-darwin) printf '%s\n' "cj_stdx_darwin_aarch64_llvm" ;;
    x86_64-w64-mingw32) printf '%s\n' "windows_x86_64_cjnative" ;;
    aarch64-linux-ohos) printf '%s\n' "linux_ohos_aarch64_cjnative" ;;
    aarch64-linux-ohos-cjnative) printf '%s\n' "linux_ohos_aarch64_cjnative" ;;
    *)
      return 1
      ;;
  esac
}

stdx_release_platform_for_target() {
  case "$1" in
    x86_64-unknown-linux-gnu) printf '%s\n' "linux-x64" ;;
    aarch64-unknown-linux-gnu) printf '%s\n' "linux-aarch64" ;;
    x86_64-apple-darwin) printf '%s\n' "mac-x64" ;;
    aarch64-apple-darwin) printf '%s\n' "mac-aarch64" ;;
    x86_64-w64-mingw32) printf '%s\n' "windows-x64" ;;
    aarch64-linux-ohos) printf '%s\n' "ohos-aarch64" ;;
    aarch64-linux-ohos-cjnative) printf '%s\n' "ohos-aarch64" ;;
    *)
      return 1
      ;;
  esac
}

requires_deveco_target() {
  case "$1" in
    aarch64-linux-ohos|aarch64-linux-ohos-cjnative) return 0 ;;
    *) return 1 ;;
  esac
}

stdx_prefers_release_bundle_for_target() {
  case "$1" in
    x86_64-apple-darwin|aarch64-apple-darwin|x86_64-w64-mingw32|aarch64-linux-ohos|aarch64-linux-ohos-cjnative)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_effective_stdx_release_version() {
  if [ -n "$STDX_RELEASE_VERSION" ]; then
    printf '%s\n' "$STDX_RELEASE_VERSION"
    return 0
  fi

  for target_triple in $STDX_TARGETS; do
    if stdx_prefers_release_bundle_for_target "$target_triple"; then
      printf '%s\n' "1.0.0.1"
      return 0
    fi
  done

  return 1
}

stdx_target_output_exists() {
  stdx_root="$1"
  target_triple="$2"
  alias_name="$(stdx_alias_name_for_target "$target_triple" || true)"

  [ -n "$alias_name" ] || return 0
  [ -d "$stdx_root/$alias_name/static/stdx" ] && return 0

  alias_source="$(find_stdx_alias_source "$stdx_root" "$alias_name" || true)"
  [ -n "$alias_source" ] && [ -d "$alias_source/static/stdx" ]
}

list_stdx_outputs() {
  stdx_root="$1"
  [ -d "$stdx_root" ] || return 0

  find "$stdx_root" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null \
    | sort \
    | tr '\n' ',' \
    | sed 's/,$//'
}

verify_requested_stdx_targets() {
  stdx_root="$1"

  for target_triple in $STDX_TARGETS; do
    alias_name="$(stdx_alias_name_for_target "$target_triple" || true)"
    [ -n "$alias_name" ] || continue

    if [ ! -d "$stdx_root/$alias_name/static/stdx" ]; then
      available_outputs="$(list_stdx_outputs "$stdx_root" || true)"
      [ -n "$available_outputs" ] || available_outputs="none"
      annotate_github_error "stdx output for $target_triple is unavailable under $stdx_root (available: $available_outputs)"
      echo "stdx output for $target_triple is unavailable under $stdx_root (available: $available_outputs)" >&2
      exit 1
    fi
  done
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

download_file_with_cache() {
  download_url="$1"
  cache_file="$2"

  mkdir -p "$(dirname "$cache_file")"
  if [ -f "$cache_file" ]; then
    return 0
  fi

  curl -L --fail "$download_url" -o "$cache_file"
}

extract_top_level_dir() {
  archive_path="$1"
  stage_dir="$2"

  rm -rf "$stage_dir"
  mkdir -p "$stage_dir"
  extract_archive "$archive_path" "$stage_dir"

  top_level_dir="$(find "$stage_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1 || true)"
  [ -n "$top_level_dir" ] && [ -d "$top_level_dir" ] || {
    echo "could not find extracted top-level directory in $archive_path" >&2
    exit 1
  }

  printf '%s\n' "$top_level_dir"
}

link_or_copy_alias() {
  source_dir="$1"
  alias_path="$2"

  rm -rf "$alias_path"
  if ln -s "$(basename "$source_dir")" "$alias_path" 2>/dev/null; then
    return 0
  fi

  cp -R "$source_dir" "$alias_path"
}

install_stdx_release_for_target() {
  target_triple="$1"
  release_version="$2"
  release_root="$3"

  alias_name="$(stdx_alias_name_for_target "$target_triple" || true)"
  release_platform="$(stdx_release_platform_for_target "$target_triple" || true)"
  [ -n "$alias_name" ] || return 1
  [ -n "$release_platform" ] || return 1

  release_cache_dir="${HOME:-$ROOT_DIR}/.cangjie_stdx/v${release_version}"
  release_filename="cangjie-stdx-${release_platform}-${release_version}.zip"
  release_url="https://gitcode.com/Cangjie/cangjie_stdx/releases/download/v${release_version}/${release_filename}"
  release_archive="${release_cache_dir}/${release_filename}"
  release_stage="${release_cache_dir}/${release_filename}.unpack"
  final_dir="${release_root}/cangjie-stdx-${release_platform}-${release_version}"

  download_file_with_cache "$release_url" "$release_archive"
  top_level_dir="$(extract_top_level_dir "$release_archive" "$release_stage")"

  mkdir -p "$release_root"
  rm -rf "$final_dir" "$release_root/$alias_name"
  mv "$top_level_dir" "$final_dir"
  link_or_copy_alias "$final_dir" "$release_root/$alias_name"
  rm -rf "$release_stage"
}

install_archive_root() {
  archive_url="$1"
  install_dir="$2"
  archive_name="$3"

  parent_dir="$(dirname "$install_dir")"
  archive_path="${parent_dir}/${archive_name}"
  stage_dir="${parent_dir}/${archive_name}.unpack"

  rm -rf "$install_dir" "$stage_dir"
  mkdir -p "$stage_dir"
  curl -L --fail "$archive_url" -o "$archive_path"
  extract_archive "$archive_path" "$stage_dir"

  first_entry="$(find "$stage_dir" -mindepth 1 -maxdepth 1 | head -n 1)"
  [ -n "$first_entry" ] || {
    echo "failed to unpack archive from $archive_url" >&2
    exit 1
  }

  if [ -d "$first_entry" ] && [ "$(find "$stage_dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = "1" ]; then
    mv "$first_entry" "$install_dir"
  else
    mkdir -p "$install_dir"
    cp -R "$stage_dir"/. "$install_dir"/
  fi

  rm -rf "$stage_dir" "$archive_path"
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
    --deveco-sdk-url)
      DEVECO_SDK_URL="${2:-}"
      shift 2
      ;;
    --deveco-dir)
      DEVECO_DIR="${2:-}"
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
    --stdx-release-version)
      STDX_RELEASE_VERSION="${2:-}"
      shift 2
      ;;
    --stdx-target)
      append_stdx_target "${2:-}"
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
DEVECO_PARENT="$(dirname "$DEVECO_DIR")"
STDX_PARENT="$(dirname "$STDX_DIR")"

mkdir -p "$SDK_PARENT" "$DEVECO_PARENT" "$STDX_PARENT"

if ! cangjie_driver >/dev/null 2>&1; then
  install_archive_root "$SDK_URL" "$SDK_DIR" "cangjie-sdk.tar.gz"
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
export PATH="$(join_path_entries "$CANGJIE_BIN_DIR" "$CANGJIE_TOOLS_DIR" "$PATH")"

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
  MINGW*|MSYS*|CYGWIN*)
    export PATH="$(join_path_entries "$RUNTIME_LIB_DIR" "$TOOLS_LIB_DIR" "$PATH")"
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

deveco_required=0
for target_triple in $STDX_TARGETS; do
  if requires_deveco_target "$target_triple"; then
    deveco_required=1
    break
  fi
done

if [ "$deveco_required" = "1" ]; then
  if [ ! -d "$DEVECO_DIR" ] && [ -n "$DEVECO_SDK_URL" ]; then
    install_archive_root "$DEVECO_SDK_URL" "$DEVECO_DIR" "deveco-cangjie-sdk.tar.gz"
  fi

  if [ -d "$DEVECO_DIR" ]; then
    export DEVECO_CANGJIE_HOME="$DEVECO_DIR"
  fi

  [ -n "${DEVECO_CANGJIE_HOME:-}" ] || {
    echo "DEVECO_CANGJIE_HOME is required for OpenHarmony targets" >&2
    exit 1
  }
fi

EFFECTIVE_STDX_RELEASE_VERSION="$(resolve_effective_stdx_release_version || true)"
STDX_RELEASE_ROOT="${STDX_PARENT}/cangjie_stdx_release"
if [ -n "$EFFECTIVE_STDX_RELEASE_VERSION" ] && [ -n "$STDX_TARGETS" ]; then
  rm -rf "$STDX_RELEASE_ROOT"
  mkdir -p "$STDX_RELEASE_ROOT"

  for target_triple in $STDX_TARGETS; do
    install_stdx_release_for_target "$target_triple" "$EFFECTIVE_STDX_RELEASE_VERSION" "$STDX_RELEASE_ROOT"
  done

  export CANGJIE_STDX_PATH="$STDX_RELEASE_ROOT"
  verify_requested_stdx_targets "$CANGJIE_STDX_PATH"

  if [ -n "${GITHUB_ENV:-}" ]; then
    {
      echo "CANGJIE_HOME=$CANGJIE_HOME"
      echo "CANGJIE_STDX_PATH=$CANGJIE_STDX_PATH"
      if [ -n "${DEVECO_CANGJIE_HOME:-}" ]; then
        echo "DEVECO_CANGJIE_HOME=$DEVECO_CANGJIE_HOME"
      fi
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
      if [ -n "$RUNTIME_LIB_DIR" ]; then
        echo "$RUNTIME_LIB_DIR"
      fi
      if [ -n "$TOOLS_LIB_DIR" ]; then
        echo "$TOOLS_LIB_DIR"
      fi
    } >> "$GITHUB_PATH"
  fi

  printf '%s\n' "$CANGJIE_HOME"
  exit 0
fi

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

if [ -n "$STDX_TARGETS" ]; then
  for target_triple in $STDX_TARGETS; do
    if [ "$FORCE_STDX_BUILD" != "1" ] && stdx_target_output_exists "$STDX_DIR/target" "$target_triple"; then
      continue
    fi

    (
      cd "$STDX_DIR"
      require_command_success "stdx cjpm build --target $target_triple" "$CJPM_BIN" build --target "$target_triple"
    )
  done
elif [ "$FORCE_STDX_BUILD" = "1" ] || [ ! -d "$STDX_DIR/target" ]; then
  (
    cd "$STDX_DIR"
    require_command_success "stdx cjpm build" "$CJPM_BIN" build
  )
fi

export CANGJIE_STDX_PATH="$(resolve_stdx_root || printf '%s\n' "$STDX_DIR/target")"
if [ -d "$CANGJIE_STDX_PATH" ]; then
  ensure_stdx_alias "$CANGJIE_STDX_PATH" "linux_x86_64_llvm"
  ensure_stdx_alias "$CANGJIE_STDX_PATH" "linux_aarch64_llvm"
  ensure_stdx_alias "$CANGJIE_STDX_PATH" "cj_stdx_darwin_x86_64_llvm"
  ensure_stdx_alias "$CANGJIE_STDX_PATH" "cj_stdx_darwin_aarch64_llvm"
  ensure_stdx_alias "$CANGJIE_STDX_PATH" "windows_x86_64_cjnative"
  ensure_stdx_alias "$CANGJIE_STDX_PATH" "linux_ohos_aarch64_cjnative"
fi

verify_requested_stdx_targets "$CANGJIE_STDX_PATH"

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "CANGJIE_HOME=$CANGJIE_HOME"
    echo "CANGJIE_STDX_PATH=$CANGJIE_STDX_PATH"
    if [ -n "${DEVECO_CANGJIE_HOME:-}" ]; then
      echo "DEVECO_CANGJIE_HOME=$DEVECO_CANGJIE_HOME"
    fi
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
    if [ -n "$RUNTIME_LIB_DIR" ]; then
      echo "$RUNTIME_LIB_DIR"
    fi
    if [ -n "$TOOLS_LIB_DIR" ]; then
      echo "$TOOLS_LIB_DIR"
    fi
  } >> "$GITHUB_PATH"
fi

printf '%s\n' "$CANGJIE_HOME"
