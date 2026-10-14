#!/usr/bin/env bash
# build-config.sh — render a sing-box client config from a subscription JSON.
#
# Sourceable. Usage: build_config <sub-json-path>  (config JSON on stdout).
# route.final = FINAL_TAG if set, else the first urltest group in the sub.
# Kept outbounds = final + transitive deps (.outbounds[] refs, .detour).
# Routing/DNS are fixed minimal (system DNS, no rules) — the sub's own
# routing/DNS blocks are ignored entirely.
# The sub's urltest groups probe gstatic every 30s and fail over on their own —
# no external probe machinery needed.
set -euo pipefail

build_config() {
    local sub_path="$1"
    [[ -r "$sub_path" ]] || { log "build_config: $sub_path not readable"; return 1; }

    local final
    final="${FINAL_TAG:-$(jq -r '[.outbounds[]? | select(.type == "urltest")][0].tag // empty' "$sub_path")}"
    [[ -n "$final" ]] || { log "build_config: no urltest group found in subscription"; return 1; }

    local known="[\"$final\"]" frontier="[\"$final\"]"
    while :; do
        local new_arr additions
        new_arr=$(jq --argjson f "$frontier" '
            .outbounds
            | map(select(.tag as $t | $f | index($t)))
            | map(
                ((.outbounds // []) | map(select(. != null and . != "")))
                + [((.detour // "") | select(. != ""))]
              )
            | flatten
            | map(select(. != null and . != ""))
            | unique
        ' "$sub_path")
        additions=$(jq -n --argjson n "$new_arr" --argjson k "$known" '$n - $k')
        [[ "$(echo "$additions" | jq 'length')" == "0" ]] && break
        known=$(jq -n --argjson k "$known" --argjson a "$additions" '$k + $a | unique')
        frontier="$additions"
    done

    # The sub is fed via --slurpfile, never argv: execve caps one arg at ~128KB
    # and real subscriptions outgrow that ("Argument list too long").
    jq -S -n \
        --slurpfile sub "$sub_path" \
        --arg w "$final" \
        --argjson kept "$known" \
        --arg lvl "${LOG_LEVEL:-warn}" \
        '
        ($sub[0].outbounds // []) as $all_outbounds
        | ($all_outbounds | map(select(.tag as $t | $kept | index($t))) | map(del(.domain_resolver))) as $kept_outbounds
        | {
            log: {level: $lvl},
            inbounds: [{
                type: "mixed",
                tag: "socks-in",
                listen: "::",
                listen_port: 1081
            }],
            outbounds: $kept_outbounds,
            route: {
                final: $w,
                rules: []
            }
          }
        '
}
