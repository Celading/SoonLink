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

patch_ignite_tls_api() {
  file="$IGNITE_DIR/src/api2/tls.cj"
  [ -f "$file" ] || return 0

  sedi '/import stdx.crypto.keys.GeneralPrivateKey/d' "$file"
  sedi 's/let certKey = GeneralPrivateKey.decodeFromPem(keyPem)/var tlsConfig = buildTlsServerConfigFromPemWithCompat(certChain, keyPem)/' "$file"
  sedi '/var tlsConfig = TlsServerConfig(certChain, certKey)/d' "$file"
  sedi 's/X509Certificate.decodeFromPem, GeneralPrivateKey.decodeFromPem/X509Certificate.decodeFromPem and a compatibility private-key helper/' "$file"
}

write_lisi_helper
write_ignite_helper
patch_lisi_tls_tool
patch_ignite_tls_api
