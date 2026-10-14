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

    # One jq computes the closure AND renders. Nothing payload-sized ever rides
    # in argv: execve caps one arg at ~128KB and both the sub and the closure
    # list outgrow that ("Argument list too long"). The sub enters via
    # --slurpfile; the closure loops stay inside jq.
    jq -S -n \
        --slurpfile sub "$sub_path" \
        --arg w "$final" \
        --arg lvl "${LOG_LEVEL:-warn}" \
        '
        def deps($all; $k):
            $all
            | map(select(.tag as $t | $k | index($t)))
            | map([
                  (.detour // empty),
                  ((.outbounds // []) | .[] | select(type == "string" and . != ""))
                ])
            | flatten
            | unique
            - $k;

        ($sub[0].outbounds // []) as $all_outbounds
        | ([$w]
           | until(
                 (deps($all_outbounds; .) | length) == 0;
                 . + deps($all_outbounds; .) | unique
             )) as $kept
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
