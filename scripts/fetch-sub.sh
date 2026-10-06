#!/usr/bin/env bash
# fetch-sub.sh — fetch the BPB subscription JSON. Sourceable.
# Exit codes: 0 ok, 10 fetch failed, 11 not JSON, 12 no urltest outbounds.
set -euo pipefail

fetch_sub() {
    local sub_url="${SUB_URL:?SUB_URL required}"
    case "$sub_url" in
        sing-box://*) sub_url="${sub_url#sing-box://import-remote-profile?url=}"; sub_url="${sub_url%%#*}" ;;
    esac

    local body
    if ! body=$(curl -fsSL --max-time 30 "$sub_url" 2>/dev/null); then
        log "fetch_sub: curl failed for sub endpoint"
        return 10
    fi

    if ! printf '%s' "$body" | jq empty >/dev/null 2>&1; then
        log "fetch_sub: expected JSON, got: $(printf '%s' "$body" | head -c 80)"
        return 11
    fi

    local urltests
    urltests=$(printf '%s' "$body" | jq -r '[.outbounds[]? | select(.type == "urltest")] | length')
    if (( urltests < 1 )); then
        log "fetch_sub: no urltest outbounds in subscription"
        return 12
    fi

    printf '%s' "$body"
}
