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

copy_tree() {
  src_dir="$1"
  dest_dir="$2"
  mkdir -p "$dest_dir"
  rsync -a --delete \
    --exclude '.git' \
    --exclude 'target' \
    --exclude 'build' \
    --exclude 'dist' \
    --exclude '_helper' \
    --exclude 'gitTemp' \
    --exclude 'cjpm.lock' \
    --exclude '.DS_Store' \
    "$src_dir"/ "$dest_dir"/
}

copy_tree "$ROOT_DIR" "$OUTPUT_DIR/SoonLink-Core"
copy_tree "$IGNITE_DIR" "$OUTPUT_DIR/Ignite0500"
copy_tree "$LISI_DIR" "$OUTPUT_DIR/lisi"
copy_tree "$JINGUISSL_DIR" "$OUTPUT_DIR/jinguiSSL"

printf '%s\n' "$OUTPUT_DIR"
