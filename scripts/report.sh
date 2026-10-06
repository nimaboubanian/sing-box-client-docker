#!/usr/bin/env bash
# report.sh — quick diagnostics. Invoked via `docker exec sing-box-client report.sh`.
set -uo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/sing-box/config.json}"
CANONICAL_PORT="${CANONICAL_PORT:-1081}"

echo "== Process =="
pgrep -af sing-box || echo "  sing-box NOT RUNNING"

echo
echo "== Config in use =="
if [[ -r "$CONFIG_FILE" ]]; then
    jq -r '"  route.final:    \(.route.final)",
           "  outbounds:      \(.outbounds | length)",
           "  listen:         \(.inbounds[0].listen):\(.inbounds[0].listen_port)"' "$CONFIG_FILE"
else
    echo "  (no config at $CONFIG_FILE — fetch or render failed; see docker logs)"
fi

echo
echo "== Exit IP (via SOCKS5 127.0.0.1:$CANONICAL_PORT) =="
ip=$(curl --socks5-hostname "127.0.0.1:$CANONICAL_PORT" --max-time 10 -s 'https://api.ipify.org' 2>/dev/null) \
    && echo "  $ip" || echo "  unreachable"
