#!/usr/bin/env bash
set -euo pipefail

PROXY="${BUILD_PROXY:-http://127.0.0.1:1080}"
BUILDER=proxied-$$

trap 'docker buildx rm --force "$BUILDER" >/dev/null 2>&1 || true' EXIT

docker buildx create --name "$BUILDER" --driver docker-container \
  --driver-opt network=host \
  --driver-opt "env.HTTP_PROXY=$PROXY" \
  --driver-opt "env.HTTPS_PROXY=$PROXY" >/dev/null

export BUILD_PROXY="$PROXY" BUILDX_BUILDER="$BUILDER"
docker compose build "$@"
echo done
