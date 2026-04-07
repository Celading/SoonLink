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

write_lisi_helper() {
  file="$WORKSPACE_DIR/lisi/src/net/TlsTool/private_key_compat.cj"
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
  file="$WORKSPACE_DIR/Ignite0500/src/api2/tls_private_key_compat.cj"
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
  file="$WORKSPACE_DIR/lisi/src/net/TlsTool/index.cj"
  [ -f "$file" ] || return 0

  sedi '/import stdx.crypto.keys.GeneralPrivateKey/d' "$file"
  sedi 's/let certKey = GeneralPrivateKey.decodeFromPem(keyPem)/var tlsConfig = buildTlsServerConfigFromPemWithCompat(certChain, keyPem)/' "$file"
  sedi '/var tlsConfig = TlsServerConfig(certChain, certKey)/d' "$file"
  sedi 's/X509Certificate.decodeFromPem、GeneralPrivateKey.decodeFromPem/X509Certificate.decodeFromPem、兼容私钥解码 helper/' "$file"
}

patch_ignite_tls_api() {
  file="$WORKSPACE_DIR/Ignite0500/src/api2/tls.cj"
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
