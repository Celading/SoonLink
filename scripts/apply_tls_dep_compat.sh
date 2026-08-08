#!/bin/sh
set -eu

WORKSPACE_DIR="${1:-}"

usage() {
  cat <<'EOF'
Usage:
  apply_tls_dep_compat.sh <workspace-dir>
EOF
  exit 1
}

[ -n "$WORKSPACE_DIR" ] || usage

sedi() {
  expr="$1"
  file="$2"
  if sed --version >/dev/null 2>&1; then
    sed -i "$expr" "$file"
  else
    sed -i '' "$expr" "$file"
  fi
}

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

LISI_DIR="$(resolve_package_dir "$WORKSPACE_DIR/lisi" "lisi")"
IGNITE_DIR="$(resolve_package_dir "$WORKSPACE_DIR/Ignite0500" "ignite")"

patch_ignite_jinguissl_facade() {
  manifest="$IGNITE_DIR/cjpm.toml"
  if grep -q '^  jinguissl = {' "$manifest"; then
    sedi 's#^  jinguissl = { .*#  JinguiSSL = { path = "../jinguiSSL" }#' "$manifest"
  fi

  find "$IGNITE_DIR/src" -type f -name '*.cj' | while IFS= read -r file; do
    if grep -q '^import jinguissl\.' "$file"; then
      sedi 's/^import jinguissl\./import JinguiSSL.jinguissl./' "$file"
    fi
  done
}

patch_ignite_facade_api_moves() {
  python_bin="$(command -v python3 || command -v python || true)"
  [ -n "$python_bin" ] || return 0

  "$python_bin" - "$IGNITE_DIR" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
live_import = "import JinguiSSL.jinguissl.live.ContractTlsSessionCache\n"

tls_api = root / "src/api2/tls.cj"
if tls_api.is_file():
    lines = tls_api.read_text(encoding="utf-8").splitlines(keepends=True)
    lines = [line for line in lines if line.strip() != "ContractTlsSessionCache,"]
    if not any(line.strip() == live_import.strip() for line in lines):
        for index, line in enumerate(lines):
            if line.startswith("import JinguiSSL.jinguissl.contract."):
                lines.insert(index, live_import)
                break
    tls_api.write_text("".join(lines), encoding="utf-8")

link_test = root / "src/tests/jinguissl_contract_link_test.cj"
if link_test.is_file():
    text = link_test.read_text(encoding="utf-8")
    if "ContractTlsSessionCache" in text and live_import.strip() not in text:
        marker = "import JinguiSSL.jinguissl.contract.*\n"
        text = text.replace(marker, marker + live_import, 1)
        link_test.write_text(text, encoding="utf-8")
PY
}

write_lisi_helper() {
  file="$LISI_DIR/src/net/TlsTool/private_key_compat.cj"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<'EOF'
package lisi.net.TlsTool

import stdx.net.tls.TlsServerConfig
import stdx.crypto.x509.X509Certificate
import stdx.crypto.keys.{ECDSAPrivateKey, RSAPrivateKey, SM2PrivateKey}

func buildTlsServerConfigFromPemWithCompat(certChain: Array<X509Certificate>, keyPem: String): TlsServerConfig {
    try {
        return TlsServerConfig(certChain, RSAPrivateKey.decodeFromPem(keyPem))
    } catch (_: Exception) {}

    try {
        return TlsServerConfig(certChain, ECDSAPrivateKey.decodeFromPem(keyPem))
    } catch (_: Exception) {}

    TlsServerConfig(certChain, SM2PrivateKey.decodeFromPem(keyPem))
}
EOF
}

write_ignite_helper() {
  file="$IGNITE_DIR/src/api2/tls_private_key_compat.cj"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<'EOF'
package ignite.api2

import stdx.net.tls.TlsServerConfig
import stdx.crypto.x509.X509Certificate
import stdx.crypto.keys.{ECDSAPrivateKey, RSAPrivateKey, SM2PrivateKey}

func buildTlsServerConfigFromPemWithCompat(certChain: Array<X509Certificate>, keyPem: String): TlsServerConfig {
    try {
        return TlsServerConfig(certChain, RSAPrivateKey.decodeFromPem(keyPem))
    } catch (_: Exception) {}

    try {
        return TlsServerConfig(certChain, ECDSAPrivateKey.decodeFromPem(keyPem))
    } catch (_: Exception) {}

    TlsServerConfig(certChain, SM2PrivateKey.decodeFromPem(keyPem))
}
EOF
}

patch_lisi_tls_tool() {
  file="$LISI_DIR/src/net/TlsTool/index.cj"
  [ -f "$file" ] || return 0

  sedi '/import stdx.crypto.keys.GeneralPrivateKey/d' "$file"
  sedi 's/let certKey = GeneralPrivateKey.decodeFromPem(keyPem)/var tlsConfig = buildTlsServerConfigFromPemWithCompat(certChain, keyPem)/' "$file"
  sedi '/var tlsConfig = TlsServerConfig(certChain, certKey)/d' "$file"
  sedi 's/X509Certificate.decodeFromPem、GeneralPrivateKey.decodeFromPem/X509Certificate.decodeFromPem、兼容私钥解码 helper/' "$file"
}

strip_ignite_raw_pem_private_key_fallback() {
  file="$1"
  python_bin="$(command -v python3 || command -v python || true)"
  [ -n "$python_bin" ] || return 0

  "$python_bin" - "$file" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    lines = fh.readlines()

out = []
skip_until = None
for line in lines:
    stripped = line.strip()
    if stripped == "import stdx.crypto.common.{Pem, PemEntry, DerBlob, PrivateKey}":
        continue
    if line.startswith("class RawPemPrivateKey <: PrivateKey {"):
        skip_until = "public func tlsToIgniteErrorCode"
        continue
    if line.startswith("func decodePrivateKeyWithoutDescribeOrThrow("):
        skip_until = "func normalizeAlpnProtocolsFallback"
        continue
    if skip_until is not None:
        if line.startswith(skip_until):
            skip_until = None
            out.append(line)
        continue
    out.append(line)

with open(path, "w", encoding="utf-8") as fh:
    fh.writelines(out)
PY
}

patch_ignite_tls_api() {
  file="$IGNITE_DIR/src/api2/tls.cj"
  [ -f "$file" ] || return 0

  sedi '/import stdx.crypto.keys.GeneralPrivateKey/d' "$file"
  sedi 's/let certKey = GeneralPrivateKey.decodeFromPem(keyPem)/var tlsConfig = buildTlsServerConfigFromPemWithCompat(certChain, keyPem)/' "$file"
  sedi 's/let certKey = decodePrivateKeyWithoutDescribeOrThrow(material.keyPem)/var tlsConfig = buildTlsServerConfigFromPemWithCompat(certChain, material.keyPem)/' "$file"
  sedi '/var tlsConfig = TlsServerConfig(certChain, certKey)/d' "$file"
  sedi 's/X509Certificate.decodeFromPem, GeneralPrivateKey.decodeFromPem/X509Certificate.decodeFromPem and a compatibility private-key helper/' "$file"
  strip_ignite_raw_pem_private_key_fallback "$file"
}

patch_ignite_jinguissl_facade
patch_ignite_facade_api_moves
write_lisi_helper
write_ignite_helper
patch_lisi_tls_tool
patch_ignite_tls_api
