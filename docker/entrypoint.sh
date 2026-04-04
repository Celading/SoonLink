#!/bin/sh
set -eu

copy_if_missing() {
  src_path="$1"
  dest_path="$2"

  if [ ! -f "$dest_path" ] && [ -f "$src_path" ]; then
    mkdir -p "$(dirname "$dest_path")"
    cp "$src_path" "$dest_path"
  fi
}

: "${SOONLINK_CONFIG_FILE:=/app/runtime/config/soonlink.toml}"
: "${SOONLINK_DEVICE_REGISTRY_FILE:=/app/runtime/config/devices.json}"
: "${SOONLINK_TEMP_DIR:=/app/runtime/tmp}"
: "${SOONLINK_LOG_DIR:=/app/runtime/logs}"
: "${SOONLINK_LOCAL_ROOT_DIR:=/app/data}"
: "${SOONLINK_RELAY_CACHE_DIR:=/app/runtime/cache/relay}"
: "${SOONLINK_FAVORITES_TOML_FILE:=/app/runtime/config/favorites.toml}"
: "${SOONLINK_WHITELIST_TOML_FILE:=/app/runtime/config/whitelist.toml}"

mkdir -p \
  "$(dirname "$SOONLINK_CONFIG_FILE")" \
  "$(dirname "$SOONLINK_DEVICE_REGISTRY_FILE")" \
  "$(dirname "$SOONLINK_FAVORITES_TOML_FILE")" \
  "$(dirname "$SOONLINK_WHITELIST_TOML_FILE")" \
  "$SOONLINK_TEMP_DIR" \
  "$SOONLINK_LOG_DIR" \
  "$SOONLINK_RELAY_CACHE_DIR" \
  "$SOONLINK_LOCAL_ROOT_DIR"

copy_if_missing /app/config/soonlink.toml "$SOONLINK_CONFIG_FILE"
copy_if_missing /app/config/devices.json "$SOONLINK_DEVICE_REGISTRY_FILE"

exec /app/soonlnk "$@"
