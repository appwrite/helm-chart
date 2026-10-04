#!/usr/bin/env bash
# Checks that an ingress controller or Gateway routes Appwrite's hostnames and
# paths to the right components.
#
# Usage: hack/routes.sh <domain> [controller-namespace] [controller-service] [--header-match]
# Requires: kubectl, curl.
set -euo pipefail

DOMAIN="$1"
NAMESPACE="${2:-traefik}"
SERVICE="${3:-traefik}"
HEADER_MATCH="${4:-}"
PORT="${ROUTES_PORT:-18081}"

kubectl -n "$NAMESPACE" port-forward "svc/$SERVICE" "$PORT:80" >/dev/null 2>&1 &
pf_pid=$!
trap 'kill $pf_pid 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do
  curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break
  sleep 1
done

failures=0
# expect DESCRIPTION HOST PATH PATTERN [extra curl args...]
expect() {
  local description=$1 host=$2 path=$3 pattern=$4
  shift 4
  local out
  out=$(curl -sS --max-time 10 -i "http://127.0.0.1:$PORT$path" -H "Host: $host" "$@" 2>&1 | LC_ALL=C tr -d '\0' || true)
  if grep -qiE "$pattern" <<<"$out"; then
    echo "ok    $description"
  else
    echo "FAIL  $description (expected /$pattern/)"
    head -15 <<<"$out" | sed 's/^/      /'
    failures=$((failures + 1))
  fi
}

# The API always sends Appwrite's CORS headers (X-Appwrite-Session); the
# console serves HTML without them. Unknown preview hosts get the API's 404
# page and unknown custom domains a redirect, which still identifies the API.
api='Access-Control-Expose-Headers: X-Appwrite-Session'
expect "API on /v1"                   "$DOMAIN" /v1/health/version '"version":"'
expect "API on /.well-known"          "$DOMAIN" /.well-known/acme-challenge/x "$api"
expect "console on /"                 "$DOMAIN" / '<html|<!doctype html'
expect "realtime on /v1/realtime"     "$DOMAIN" '/v1/realtime?project=console&channels%5B%5D=account' 'HTTP/1.1 101' \
  --http1.1 --max-time 3 -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ=='
expect "API on function previews"     "abc.functions.$DOMAIN" / "$api"
expect "API on site previews"         "abc.sites.$DOMAIN" / "$api"
expect "API on custom domains"        "custom.example.net" / "$api"
if [[ "$HEADER_MATCH" == --header-match ]]; then
  expect "API for x-appwrite-hostname" "$DOMAIN" / "$api" -H 'x-appwrite-hostname: preview.example.net'
fi

if (( failures > 0 )); then
  echo "$failures route(s) failed"
  exit 1
fi
echo "all routes OK"
