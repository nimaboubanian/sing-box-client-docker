# sing-box-client-docker

A single Docker container that fetches a BPB subscription, renders a sing-box client config, and runs sing-box exposing SOCKS5 + HTTP CONNECT on `127.0.0.1:1081`.

Outbound selection and failover are sing-box's own `urltest` groups (probed every 30s, continuously) — this container adds nothing on top. If sing-box dies, docker's `restart: unless-stopped` brings it back and the config is re-rendered from a fresh fetch.

Joined as a peer to the SoftEther-client-docker project on its external `vpn-net` (this container sits at `172.30.0.11`). It does **not** use the softether container as an outbound.

## Quick start

```sh
cp .env.example .env
# edit .env: set SUB_URL=...
docker compose up -d --build
docker logs -f sing-box-client   # look for: "starting sing-box (final: …)"
```

## Verify

```sh
docker exec sing-box-client report.sh
curl --socks5-hostname 127.0.0.1:1081 https://api.ipify.org   # SOCKS5
curl -x http://127.0.0.1:1081 https://api.ipify.org           # HTTP CONNECT, same port
```

Both should return the proxy's exit IP, different from your host's public IP.

## Update the subscription

```sh
docker compose restart sing-box-client
```

## Stop

```sh
docker compose down
```

## Environment variables

| Name | Required | Default | Description |
|---|---|---|---|
| `SUB_URL` | **yes** | — | Subscription URL; must serve sing-box JSON containing `urltest` groups |
| `LOG_LEVEL` | no | `warn` | sing-box log level |
| `FINAL_TAG` | no | first `urltest` in the sub | Which `urltest` group is `route.final` (e.g. `💦 Best Ping 🚀`, `💦 Best Ping D 🚀`, or a chained `💦 🔗 …` variant) |
| `VPN_NET_NAME` | no | `softether-client-docker_vpn-net` | External Docker network name |

## Architecture

```
┌─────── host 127.0.0.1 ────────┐
│   SOCKS5 + HTTP :1081         │
└──────────────┬────────────────┘
               │ (docker bridge)
┌──────────────▼────────────── sing-box-client container ─────┐
│                                                             │
│  supervisor.sh ──► fetch_sub ──► sub JSON                   │
│       │                                                     │
│       └──► build_config ──► /etc/sing-box/config.json      │
│                 │                                           │
│                 └──► exec sing-box run                      │
│                         route.final = urltest group         │
│                         (30s continuous probe + failover)   │
└──────────────┬──────────────────────────────────────────────┘
               │ (vpn-net, IP 172.30.0.11 — peer only, no L3 dependency)
```

## Troubleshooting

### Container restarts, logs show `fetch_sub: curl failed`

The sub endpoint is unreachable from the container (network/proxy issue). Verify: `docker exec sing-box-client curl -fsSL "$SUB_URL" -o /dev/null && echo ok`.

### Logs show `fetch_sub: expected JSON`

The URL serves something other than sing-box JSON (e.g. a base64 v2ray sub). Use a BPB `?app=sing-box` endpoint.

### Logs show `fetch_sub: no urltest outbounds`

The sub has no `urltest` groups; there is nothing to auto-select. This container requires them.

### `curl` through 1081 returns the host's exit IP

Check `docker exec sing-box-client report.sh` — if the exit IP is unreachable, the group's servers may all be down; try `FINAL_TAG` with another group (e.g. a `💦 🔗 …` chained variant) and restart.

### Connection refused on 127.0.0.1:1081

The compose file binds host loopback only — intentional. Connecting from other machines is refused by design.

## Files

| Path | Purpose |
|---|---|
| `Dockerfile` | Alpine 3.20 + sing-box 1.14.2 |
| `compose.yaml` | External `vpn-net`, host loopback port |
| `.env.example` | Sample env |
| `scripts/supervisor.sh` | Entrypoint: fetch → render → exec sing-box |
| `scripts/fetch-sub.sh` | Subscription fetcher + validation |
| `scripts/build-config.sh` | Config renderer (kept-outbound extraction; fixed minimal routing/DNS — sub's routing/DNS ignored) |
| `scripts/report.sh` | Quick diagnostics |
| `docs/superpowers/specs/` | Design document |

## License

MIT.
