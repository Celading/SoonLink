#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: package_release_bundle.sh --root <project> --binary <path> --target <triple> \
  --version <version> --output-dir <dir> --runtime-root <dir> [--stdx-root <dir>]
EOF
  exit 2
}

ROOT_DIR=""
BINARY=""
TARGET=""
VERSION=""
OUTPUT_DIR=""
RUNTIME_ROOT=""
STDX_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_DIR=$2; shift 2 ;;
    --binary) BINARY=$2; shift 2 ;;
    --target) TARGET=$2; shift 2 ;;
    --version) VERSION=$2; shift 2 ;;
    --output-dir) OUTPUT_DIR=$2; shift 2 ;;
    --runtime-root) RUNTIME_ROOT=$2; shift 2 ;;
    --stdx-root) STDX_ROOT=$2; shift 2 ;;
    *) usage ;;
  esac
done

[[ -d "$ROOT_DIR" && -f "$BINARY" && -n "$TARGET" && -n "$VERSION" && -n "$OUTPUT_DIR" ]] || usage
[[ -d "$RUNTIME_ROOT" ]] || { echo "runtime root not found: $RUNTIME_ROOT" >&2; exit 1; }

platform=""
binary_name="soonlnk"
case "$TARGET" in
  x86_64-unknown-linux-gnu) platform="Linux-x86_64" ;;
  aarch64-unknown-linux-gnu) platform="Linux-aarch64" ;;
  aarch64-apple-darwin) platform="macOS-aarch64" ;;
  x86_64-apple-darwin) platform="macOS-x86_64" ;;
  x86_64-w64-mingw32) platform="Windows-x86_64"; binary_name="soonlnk.exe" ;;
  aarch64-w64-mingw32) platform="Windows-aarch64"; binary_name="soonlnk.exe" ;;
  aarch64-linux-ohos) platform="OHOS-aarch64" ;;
  x86_64-linux-ohos) platform="OHOS-x86_64" ;;
  *) echo "unsupported release target: $TARGET" >&2; exit 2 ;;
esac

stage_name="SoonLnk-${VERSION}_${platform}"
if [[ "$TARGET" == *-w64-mingw32 ]]; then
  stage_name="${stage_name}-exe"
fi
stage_root="$OUTPUT_DIR/$stage_name"
archive_root="$OUTPUT_DIR/$stage_name"
rm -rf "$stage_root" "$archive_root.zip" "$archive_root.tar.gz"
mkdir -p "$stage_root/lib" "$OUTPUT_DIR"

copy_tree() {
  local source=$1 destination=$2
  [[ -d "$source" ]] || return 0
  mkdir -p "$destination"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude='.git/' --exclude='.DS_Store' "$source/" "$destination/"
  else
    tar --exclude='.git' --exclude='.DS_Store' -cf - -C "$source" . | tar -xf - -C "$destination"
  fi
}

for path in LICENSE README.md README-EN.MD CHANGELOG.MD CHANGELOG-EN.MD config web docker/entrypoint.sh compose.yaml compose.release.yaml .env.example; do
  if [[ -d "$ROOT_DIR/$path" ]]; then
    copy_tree "$ROOT_DIR/$path" "$stage_root/$path"
  elif [[ -f "$ROOT_DIR/$path" ]]; then
    mkdir -p "$(dirname "$stage_root/$path")"
    cp "$ROOT_DIR/$path" "$stage_root/$path"
  fi
done

cp "$BINARY" "$stage_root/$binary_name"
chmod 0755 "$stage_root/$binary_name"

copy_runtime_files() {
  local source_root=$1
  [[ -d "$source_root" ]] || return 0
  while IFS= read -r library; do
    [[ -f "$library" ]] || continue
    cp -f "$library" "$stage_root/lib/$(basename "$library")"
  done < <(find "$source_root" -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.dylib' -o -name '*.dll' \) -print)
  while IFS= read -r library_link; do
    [[ -L "$library_link" ]] || continue
    # Release archives must not retain links back into the temporary SDK tree.
    cp -L "$library_link" "$stage_root/lib/$(basename "$library_link")"
  done < <(find "$source_root" -type l \( -name '*.so' -o -name '*.so.*' -o -name '*.dylib' -o -name '*.dll' \) -print)
}

copy_runtime_files "$RUNTIME_ROOT"
copy_runtime_files "$(dirname "$BINARY")"
copy_runtime_files "$(dirname "$(dirname "$BINARY")")"

runtime_count=$(find "$stage_root/lib" -type f | wc -l | tr -d ' ')
[[ "$runtime_count" -gt 0 ]] || { echo "no runtime libraries were carried into bundle" >&2; exit 1; }

patch_loader() {
  case "$TARGET" in
    *-apple-darwin)
      command -v install_name_tool >/dev/null 2>&1 || { echo "install_name_tool is required for macOS bundle patching" >&2; exit 1; }
      while IFS= read -r rpath; do
        [[ -n "$rpath" && "$rpath" != '@loader_path/lib' ]] || continue
        install_name_tool -delete_rpath "$rpath" "$stage_root/$binary_name"
      done < <(otool -l "$stage_root/$binary_name" | awk '/cmd LC_RPATH/{getline; getline; print $2}')
      install_name_tool -add_rpath '@loader_path/lib' "$stage_root/$binary_name" 2>/dev/null || true
      while IFS= read -r dependency; do
        case "$dependency" in
          /usr/lib/*|/System/Library/*|@rpath/*|@loader_path/*|@executable_path/*) continue ;;
        esac
        install_name_tool -change "$dependency" "@rpath/$(basename "$dependency")" "$stage_root/$binary_name"
      done < <(otool -L "$stage_root/$binary_name" | tail -n +2 | sed -E 's/^[[:space:]]+([^ ]+).*/\1/')
      while IFS= read -r library; do
        [[ -f "$library" && ! -L "$library" ]] || continue
        install_name_tool -id "@rpath/$(basename "$library")" "$library" 2>/dev/null || true
        while IFS= read -r dependency; do
          case "$dependency" in
            /usr/lib/*|/System/Library/*|@rpath/*|@loader_path/*|@executable_path/*) continue ;;
          esac
          install_name_tool -change "$dependency" "@rpath/$(basename "$dependency")" "$library"
        done < <(otool -L "$library" | tail -n +2 | sed -E 's/^[[:space:]]+([^ ]+).*/\1/')
      done < <(find "$stage_root/lib" -type f -name '*.dylib' -print)
      if otool -l "$stage_root/$binary_name" | awk '/cmd LC_RPATH/{getline; getline; print $2}' | grep -Ev '^@loader_path/lib$' | grep -q .; then
        echo "macOS bundle retains a host-specific runtime search path" >&2
        exit 1
      fi
      if find "$stage_root/lib" -type f -name '*.dylib' -exec otool -L {} \; | grep -E '^[[:space:]]+/(Library/Frameworks/Cangjie|Users/|opt/)' >/dev/null; then
        echo "macOS bundle retains an absolute non-system dynamic-library dependency" >&2
        exit 1
      fi
      ;;
    *-unknown-linux-gnu)
      command -v patchelf >/dev/null 2>&1 || { echo "patchelf is required for Linux self-contained bundle patching" >&2; exit 1; }
      patchelf --set-rpath '$ORIGIN/lib' "$stage_root/$binary_name"
      while IFS= read -r library; do
        patchelf --set-rpath '$ORIGIN' "$library"
      done < <(find "$stage_root/lib" -type f \( -name '*.so' -o -name '*.so.*' \) -print)
      ;;
    *-w64-mingw32)
      find "$stage_root/lib" -type f -name '*.dll' -exec cp -f {} "$stage_root/" \;
      ;;
    *)
      # OHOS output is link-proof only; it is not claimed as host runtime smoke.
      ;;
  esac
}

patch_loader

cat > "$stage_root/run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
export SOONLINK_WORK_DIR="${SOONLINK_WORK_DIR:-$ROOT}"
export LD_LIBRARY_PATH="$ROOT/lib:${LD_LIBRARY_PATH:-}"
export DYLD_LIBRARY_PATH="$ROOT/lib:${DYLD_LIBRARY_PATH:-}"
exec "$ROOT/soonlnk" "$@"
EOF
chmod 0755 "$stage_root/run.sh"

cat > "$stage_root/run.cmd" <<'EOF'
@echo off
set "SOONLINK_WORK_DIR=%~dp0"
"%~dp0soonlnk.exe" %*
EOF

python3 - "$stage_root/bundle-manifest.json" "$TARGET" "$VERSION" "$binary_name" "$runtime_count" <<'PY'
import json
import pathlib
import sys

out, target, version, binary, runtime_count = sys.argv[1:]
root = pathlib.Path(out).parent
payload = {
    "schema": "soonlink-release-bundle-v1",
    "status": "self-contained-runtime-bundle",
    "target": target,
    "version": version,
    "binary": binary,
    "runtimeLibrariesCarried": int(runtime_count),
    "webpanel": {
        "included": (root / "web").is_dir(),
        "entry": "web/views/index.html",
    },
    "runtimeSmoke": "native-only-for-host-target; OHOS-link-proof-is-not-runtime-proof",
    "nonPromises": [
        "the host operating system still supplies its system libraries",
        "OHOS cross artifacts are not executed on this runner",
    ],
}
pathlib.Path(out).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

python3 - "$stage_root" "$archive_root.zip" <<'PY'
import pathlib
import sys
import zipfile

source, archive = map(pathlib.Path, sys.argv[1:])
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as output:
    for path in sorted(source.rglob("*")):
        if path.is_file():
            output.write(path, path.relative_to(source.parent))
PY
tar -czf "$archive_root.tar.gz" -C "$OUTPUT_DIR" "$stage_name"

python3 - "$archive_root.zip" "$archive_root.tar.gz" "$OUTPUT_DIR/SHA256SUMS" <<'PY'
import hashlib
import pathlib
import sys

def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

zip_path, tar_path, sums_path = map(pathlib.Path, sys.argv[1:])
with sums_path.open("w", encoding="utf-8") as output:
    for path in (zip_path, tar_path):
        output.write(f"{digest(path)}  {path.name}\n")
PY

rm -rf "$stage_root"
printf '%s\n%s\n' "$archive_root.zip" "$archive_root.tar.gz"
