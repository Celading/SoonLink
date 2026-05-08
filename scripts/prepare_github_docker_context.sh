#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR=""
IGNITE_DIR=""
LISI_DIR=""
JINGUISSL_DIR=""

usage() {
  cat <<'EOF'
Usage:
  prepare_github_docker_context.sh \
    --output <dir> \
    --ignite <dir> \
    --lisi <dir> \
    --jinguissl <dir>
EOF
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --ignite)
      IGNITE_DIR="${2:-}"
      shift 2
      ;;
    --lisi)
      LISI_DIR="${2:-}"
      shift 2
      ;;
    --jinguissl)
      JINGUISSL_DIR="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      ;;
  esac
done

[ -n "$OUTPUT_DIR" ] || usage
[ -n "$IGNITE_DIR" ] || usage
[ -n "$LISI_DIR" ] || usage
[ -n "$JINGUISSL_DIR" ] || usage

[ -d "$IGNITE_DIR" ] || { echo "ignite directory not found: $IGNITE_DIR" >&2; exit 1; }
[ -d "$LISI_DIR" ] || { echo "lisi directory not found: $LISI_DIR" >&2; exit 1; }
[ -d "$JINGUISSL_DIR" ] || { echo "jinguiSSL directory not found: $JINGUISSL_DIR" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"

package_name_from_manifest() {
  manifest_path="$1"
  sed -n 's/^  name = "\(.*\)"/\1/p' "$manifest_path" | head -n 1
}

resolve_package_dir() {
  repo_dir="$1"
  expected_package="$2"

  if [ -f "$repo_dir/cjpm.toml" ] && [ "$(package_name_from_manifest "$repo_dir/cjpm.toml")" = "$expected_package" ]; then
    printf '%s\n' "$repo_dir"
    return 0
  fi

  found_dir=""
  tmp_list="$(mktemp "${TMPDIR:-/tmp}/soonlink-package-dir.XXXXXX")"
  find "$repo_dir" -maxdepth 3 -type f -name 'cjpm.toml' | sort | while IFS= read -r manifest_path; do
    package_name="$(package_name_from_manifest "$manifest_path")"
    [ "$package_name" = "$expected_package" ] || continue
    printf '%s\n' "$(dirname "$manifest_path")"
  done > "$tmp_list"

  while IFS= read -r candidate_dir; do
    [ -n "$candidate_dir" ] || continue
    if [ -n "$found_dir" ] && [ "$found_dir" != "$candidate_dir" ]; then
      rm -f "$tmp_list"
      echo "multiple package roots found for $expected_package under $repo_dir" >&2
      exit 1
    fi
    found_dir="$candidate_dir"
  done < "$tmp_list"

  rm -f "$tmp_list"

  if [ -z "$found_dir" ]; then
    echo "package root for $expected_package not found under $repo_dir" >&2
    exit 1
  fi

  printf '%s\n' "$found_dir"
}

copy_tree() {
  src_dir="$1"
  dest_dir="$2"
  rm -rf "$dest_dir"
  mkdir -p "$dest_dir"
  (
    cd "$src_dir"
    tar \
      --exclude '.git' \
      --exclude 'target' \
      --exclude 'build' \
      --exclude 'dist' \
      --exclude '.cache' \
      --exclude '.vscode' \
      --exclude '.idea' \
      --exclude '.env' \
      --exclude '.cjpm_test_tmp_*' \
      --exclude 'cache' \
      --exclude 'logs' \
      --exclude 'volumes' \
      --exclude 'output' \
      --exclude '~' \
      --exclude '_helper' \
      --exclude 'gitTemp' \
      --exclude 'cjpm.lock' \
      --exclude 'cangjie-repo.toml' \
      --exclude 'module-resolve.json' \
      --exclude 'module-lock.json' \
      --exclude '.DS_Store' \
      -cf - .
  ) | (
    cd "$dest_dir"
    tar -xf -
  )
}

copy_package_tree() {
  repo_dir="$1"
  dest_dir="$2"
  expected_package="$3"

  package_dir="$(resolve_package_dir "$repo_dir" "$expected_package")"
  copy_tree "$package_dir" "$dest_dir"
}

copy_tree "$ROOT_DIR" "$OUTPUT_DIR/SoonLink-Core"
copy_package_tree "$IGNITE_DIR" "$OUTPUT_DIR/Ignite0500" "ignite"
copy_package_tree "$LISI_DIR" "$OUTPUT_DIR/lisi" "lisi"
copy_package_tree "$JINGUISSL_DIR" "$OUTPUT_DIR/jinguiSSL" "jinguissl"

sh "$ROOT_DIR/scripts/apply_tls_dep_compat.sh" "$OUTPUT_DIR"

printf '%s\n' "$OUTPUT_DIR"
