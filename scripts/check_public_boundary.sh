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
require_path "compose.yaml"
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
require_path "scripts/render_homebrew_formula.sh"
require_path "scripts/check_public_boundary.sh"
require_path ".github/workflows/core-ci.yml"
require_path ".github/workflows/release-artifacts.yml"
require_path ".github/workflows/docker-publish.yml"
require_path ".github/workflows/homebrew-ci.yml"

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

FORBIDDEN_TRACKED_PATTERN='(^|/)(_[^/]+|cache|logs|target|build|output|dist|volumes)(/|$)|^config/(devices\.json|favorites\.toml|whitelist\.toml)$|(^|/)\.git(/|$)'

if tracked_files | grep -E "$FORBIDDEN_TRACKED_PATTERN" >/dev/null 2>&1; then
  echo "internal workspace, git metadata, or runtime paths are tracked" >&2
  tracked_files | grep -E "$FORBIDDEN_TRACKED_PATTERN"
  exit 1
fi

if tracked_files | grep -E '^(Ignite|IgniteNEXT|lisi)(/|$)' >/dev/null 2>&1; then
  echo "dependency mirrors must not be tracked" >&2
  exit 1
fi

echo "public boundary check passed"
