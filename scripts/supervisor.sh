#!/usr/bin/env bash
# supervisor.sh — container entrypoint: fetch sub, render config, run sing-box.
#
# Outbound selection/failover is sing-box's own urltest (30s, continuous).
# sing-box death -> container exit -> docker restart backoff (unchanged).
# RESTART_INTERVAL (seconds) forces a scheduled refresh: re-fetch sub, re-render,
# and only then swap sing-box — a failed fetch/render never kills a healthy
# tunnel. Unset or 0 disables the scheduled refresh.
set -euo pipefail

CONFIG_DIR="/etc/sing-box"
mkdir -p "$CONFIG_DIR"

INTERVAL="${RESTART_INTERVAL:-0}"
(( INTERVAL > 0 )) || INTERVAL=100000000   # unset/0 = no scheduled refresh

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }

source /usr/local/bin/fetch-sub.sh
source /usr/local/bin/build-config.sh

SBPID=""
trap 'kill "$SBPID" 2>/dev/null; exit 0' TERM INT

first=1
while :; do
    if (( first )); then
        log "fetching subscription"
        fetch_sub > "${CONFIG_DIR}/sub.json"
        log "rendering config"
        build_config "${CONFIG_DIR}/sub.json" > "${CONFIG_DIR}/config.json"
        first=0
    fi

    log "starting sing-box (final: $(jq -r '.route.final' "${CONFIG_DIR}/config.json"))"
    sing-box run -c "${CONFIG_DIR}/config.json" &
    SBPID=$!

    while :; do
        sleep "$INTERVAL" &
        wait -n || true
        if ! kill -0 "$SBPID" 2>/dev/null; then
            wait "$SBPID" 2>/dev/null || true
            log "sing-box exited — container follows (docker restarts)"
            exit 1
        fi
        log "restart interval reached — refreshing subscription"
        if fetch_sub > "${CONFIG_DIR}/sub.new.json" \
            && build_config "${CONFIG_DIR}/sub.new.json" > "${CONFIG_DIR}/config.new.json"; then
            mv "${CONFIG_DIR}/sub.new.json" "${CONFIG_DIR}/sub.json"
            mv "${CONFIG_DIR}/config.new.json" "${CONFIG_DIR}/config.json"
            kill "$SBPID" || true
            wait "$SBPID" 2>/dev/null || true
            log "tunnel refreshed with new config"
            break
        fi
        log "refresh failed — keeping current tunnel"
    done
done
