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
  prepare_release_workspace.sh \
    --output <dir> \
    --ignite <dir> \
    --lisi <dir> \
    --jinguissl <dir>
EOF
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

ensure_windows_target() {
  manifest_path="$1"
  package_kind="$2"

  if grep -q '^\[target.x86_64-w64-mingw32\]' "$manifest_path"; then
    return 0
  fi

  {
    printf '\n'
    printf '[target.x86_64-w64-mingw32]\n'
    if [ "$package_kind" = "ignite" ]; then
      printf '  link-option = "-lcrypt32"\n'
      printf '  compile-option = "--cfg \\"ohos=false\\""\n'
    fi
    printf '  [target.x86_64-w64-mingw32.bin-dependencies]\n'
    printf '    path-option = ["${CANGJIE_STDX_PATH}/windows_x86_64_cjnative/static/stdx"]\n'
    printf '  [target.x86_64-w64-mingw32-Deprecated.bin-dependencies]\n'
    printf '    path-option = ["${CANGJIE_STDX_PATH}/cj_stdx_x86_64-w64-mingw32/static/stdx"]\n'
  } >> "$manifest_path"
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

copy_tree "$ROOT_DIR" "$OUTPUT_DIR/SoonLink-Core"
copy_tree "$IGNITE_DIR" "$OUTPUT_DIR/Ignite0500"
copy_tree "$LISI_DIR" "$OUTPUT_DIR/lisi"
copy_tree "$JINGUISSL_DIR" "$OUTPUT_DIR/jinguiSSL"

sh "$ROOT_DIR/scripts/apply_tls_dep_compat.sh" "$OUTPUT_DIR"

sedi 's#^  ignite = { .*#  ignite = { path = "../Ignite0500" }#' "$OUTPUT_DIR/SoonLink-Core/cjpm.toml"
sedi 's#^  lisi = { .*#  lisi = { path = "../lisi" }#' "$OUTPUT_DIR/SoonLink-Core/cjpm.toml"
sedi 's#^  jinguissl = { .*#  jinguissl = { path = "../jinguiSSL" }#' "$OUTPUT_DIR/Ignite0500/cjpm.toml"

ensure_windows_target "$OUTPUT_DIR/SoonLink-Core/cjpm.toml" "core"
ensure_windows_target "$OUTPUT_DIR/Ignite0500/cjpm.toml" "ignite"
ensure_windows_target "$OUTPUT_DIR/lisi/cjpm.toml" "lisi"

printf '%s\n' "$OUTPUT_DIR"
