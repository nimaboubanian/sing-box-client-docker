#!/usr/bin/env bash
# supervisor.sh — container entrypoint: fetch sub, render config, exec sing-box.
#
# Outbound selection/failover is sing-box's own urltest (30s, continuous).
# Death handling is docker's restart policy. Nothing else to supervise.
set -euo pipefail

CONFIG_DIR="/etc/sing-box"
mkdir -p "$CONFIG_DIR"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }

source /usr/local/bin/fetch-sub.sh
source /usr/local/bin/build-config.sh

log "fetching subscription"
fetch_sub > "${CONFIG_DIR}/sub.json"

log "rendering config"
build_config "${CONFIG_DIR}/sub.json" > "${CONFIG_DIR}/config.json"

log "starting sing-box (final: $(jq -r '.route.final' "${CONFIG_DIR}/config.json"))"
exec sing-box run -c "${CONFIG_DIR}/config.json"
