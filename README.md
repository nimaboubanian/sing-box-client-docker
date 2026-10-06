# sing-box-client-docker

Docker container: fetches a BPB subscription, runs sing-box as a client with SOCKS5 + HTTP CONNECT on `127.0.0.1:1081`. Outbound selection/failover is sing-box's own `urltest` groups (probed every 30s); docker restart handles crashes.

## Run

```sh
cp .env.example .env
# edit .env: set SUB_URL=...
docker compose up -d --build
docker logs -f sing-box-client   # look for: "starting sing-box (final: …)"
```

## Test

```sh
curl --socks5-hostname 127.0.0.1:1081 https://api.ipify.org   # SOCKS5
curl -x http://127.0.0.1:1081 https://api.ipify.org           # HTTP CONNECT, same port
docker exec sing-box-client report.sh                          # diagnostics
```

Both curls must return the proxy's exit IP (not your VPS's public IP).

## Env

| Name | Required | Default | Description |
|---|---|---|---|
| `SUB_URL` | **yes** | — | Subscription URL (BPB `?app=sing-box` endpoint or its `sing-box://…` link) |
| `LOG_LEVEL` | no | `warn` | sing-box log level |
| `FINAL_TAG` | no | first `urltest` in sub | Which `urltest` group to use (e.g. `💦 Best Ping 🚀` or a chained `💦 🔗 …` variant) |
| `RESTART_INTERVAL` | no | disabled | Scheduled refresh in seconds — re-fetch the sub, then swap sing-box only on success; failed refresh keeps the current tunnel |

Refresh the subscription: `docker compose restart sing-box-client`. Stop: `docker compose down`. Port is bound to host loopback only — no remote access by design.

## Shared network

Both containers join a docker network named `vpndogs` (see `compose.yaml`). Either project can come up first: the first one creates the network, the other reuses it; `docker compose down` in either project leaves the network alone while the other still uses it.

## Troubleshooting

- Restarts with `fetch_sub: curl failed` / `expected JSON` / `no urltest outbounds` — see `docker logs`: bad URL, non-sing-box sub, or a sub without `urltest` groups.
- Curl returns your own IP or hangs — all servers in the group are down; set `FINAL_TAG` to another group and restart.

## License

MIT.
