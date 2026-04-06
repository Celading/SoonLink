#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

tracked_files() {
  if git -C "$ROOT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    prefix="$(git -C "$ROOT_DIR" rev-parse --show-prefix)"
    git -C "$ROOT_DIR" ls-files | awk -v prefix="$prefix" '
      prefix == "" { print; next }
      index($0, prefix) == 1 { print substr($0, length(prefix) + 1) }
    '
  fi
}

tracked_symlinks() {
  if git -C "$ROOT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    prefix="$(git -C "$ROOT_DIR" rev-parse --show-prefix)"
    git -C "$ROOT_DIR" ls-files -s | awk -v prefix="$prefix" '
      $1 != "120000" { next }
      prefix == "" { print $4; next }
      index($4, prefix) == 1 { print substr($4, length(prefix) + 1) }
    '
  fi
}

require_path() {
  if [ ! -e "$1" ]; then
    echo "missing required path: $1" >&2
    exit 1
  fi
}

require_path "cjpm.toml"
require_path "Dockerfile"
require_path ".dockerignore"
require_path "compose.yaml"
require_path "compose.release.yaml"
require_path ".env.example"
require_path "README.md"
require_path "README-EN.MD"
require_path "CHANGELOG-EN.MD"
require_path "config"
require_path "web"
require_path "docker/entrypoint.sh"
require_path "scripts/prepare_container_bundle.sh"
require_path "scripts/prepare_homebrew_bundle.sh"
require_path "scripts/build_release_bundle.sh"
require_path "scripts/build_release_target.sh"
require_path "scripts/install_cangjie_ci.sh"
require_path "scripts/prepare_release_workspace.sh"
require_path "scripts/render_homebrew_formula.sh"
require_path "scripts/check_public_boundary.sh"
require_path ".github/workflows/core-ci.yml"
require_path ".github/workflows/release-artifacts.yml"
require_path ".github/workflows/docker-publish.yml"
require_path ".github/workflows/homebrew-ci.yml"
require_path ".github/workflows/homebrew-tap.yml"

for public_path in README.md README-EN.MD CHANGELOG.MD CHANGELOG-EN.MD LICENSE config web docker/entrypoint.sh; do
  if [ -L "$public_path" ]; then
    echo "public path must not be a symlink: $public_path" >&2
    exit 1
  fi
done

if tracked_symlinks | grep . >/dev/null 2>&1; then
  echo "tracked symlinks detected in public repo" >&2
  tracked_symlinks
  exit 1
fi

FORBIDDEN_TRACKED_PATTERN='(^|/)(_[^/]+|cache|logs|target|build|output|dist|volumes|gitTemp|\.cache|\.vscode|\.idea)(/|$)|^config/(devices\.json|favorites\.toml|whitelist\.toml)$|(^|/)\.git(/|$)|(^|/)\.DS_Store$'

if tracked_files | grep -E "$FORBIDDEN_TRACKED_PATTERN" >/dev/null 2>&1; then
  echo "internal workspace, git metadata, or runtime paths are tracked" >&2
  tracked_files | grep -E "$FORBIDDEN_TRACKED_PATTERN"
  exit 1
fi

if tracked_files | grep -E '(^|/)\.env($|(\.[^/]+)$)' | grep -vE '(^|/)\.env\.example$' >/dev/null 2>&1; then
  echo "private env files must not be tracked" >&2
  tracked_files | grep -E '(^|/)\.env($|(\.[^/]+)$)' | grep -vE '(^|/)\.env\.example$'
  exit 1
fi

if tracked_files | grep -E '^(Ignite|IgniteNEXT|lisi)(/|$)' >/dev/null 2>&1; then
  echo "dependency mirrors must not be tracked" >&2
  exit 1
fi

scan_tracked_content() {
  pattern="$1"
  temp_file="$(mktemp "${TMPDIR:-/tmp}/soonlink-boundary.XXXXXX")"

  tracked_files | while IFS= read -r path; do
    [ -f "$path" ] || continue
    [ "$path" = "scripts/check_public_boundary.sh" ] && continue
    grep -HnE "$pattern" "$path" >> "$temp_file" 2>/dev/null || true
  done

  if [ -s "$temp_file" ]; then
    cat "$temp_file"
    rm -f "$temp_file"
    return 0
  fi

  rm -f "$temp_file"
  return 1
}

USER_HOME_PREFIX='/''Users/'
VAR_FOLDERS_PREFIX='/''var/folders/'
PRIVATE_VAR_FOLDERS_PREFIX='/''private/var/folders/'
WORK_ROOT_PREFIX='Documents/''Work0'
WORKSPACE_NAME_TOKEN='Curea''teX'
LOCAL_PATH_PATTERN="${USER_HOME_PREFIX}|${VAR_FOLDERS_PREFIX}|${PRIVATE_VAR_FOLDERS_PREFIX}|${WORK_ROOT_PREFIX}|${WORKSPACE_NAME_TOKEN}"

if scan_tracked_content "$LOCAL_PATH_PATTERN" >/dev/null 2>&1; then
  echo "local machine paths leaked into tracked content" >&2
  scan_tracked_content "$LOCAL_PATH_PATTERN"
  exit 1
fi

echo "public boundary check passed"
