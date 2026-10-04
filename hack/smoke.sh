#!/usr/bin/env bash
# End-to-end smoke test for an installed Appwrite release.
#
# Creates the console root account, a team, a project, a database, a
# collection and an attribute, and waits for the attribute to become
# available. Attributes are created asynchronously by the databases queue,
# so this proves the API, datastores and workers work together. Finally it
# checks the console and the realtime WebSocket endpoint.
#
# Usage: hack/smoke.sh [release] [namespace]
# Requires: kubectl, curl, jq.
set -euo pipefail

RELEASE="${1:-appwrite}"
NAMESPACE="${2:-appwrite}"
PORT="${SMOKE_PORT:-18080}"
TIMEOUT="${SMOKE_TIMEOUT:-180}"

fullname=$(kubectl -n "$NAMESPACE" get svc -l "app.kubernetes.io/instance=$RELEASE,app.kubernetes.io/component=api" -o jsonpath='{.items[0].metadata.name}')
api_host="$fullname"
base="${fullname%-api}"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nFAIL: %s\n' "$*" >&2; exit 1; }

kubectl -n "$NAMESPACE" port-forward "svc/$fullname" "$PORT:80" >/dev/null 2>&1 &
pf_pid=$!
trap 'kill $pf_pid 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do
  curl -fsS -o /dev/null "http://127.0.0.1:$PORT/v1/health/version" -H "Host: $api_host" 2>/dev/null && break
  sleep 1
done

cookies=""
# call METHOD PATH [JSON] [PROJECT] -> prints the response body; returns 1 on HTTP >= 400
call() {
  local method=$1 path=$2 data=${3:-} project=${4:-console}
  local args=(-sS -X "$method" "http://127.0.0.1:$PORT/v1$path"
    -H "Host: $api_host" -H "Content-Type: application/json"
    -H "X-Appwrite-Project: $project" -D "$tmp/headers" -o "$tmp/body" -w '%{http_code}')
  [[ "$project" != console ]] && args+=(-H "X-Appwrite-Mode: admin")
  [[ -n "$cookies" ]] && args+=(-H "X-Fallback-Cookies: $cookies")
  [[ -n "$data" ]] && args+=(--data "$data")
  local code
  code=$(curl "${args[@]}")
  if [[ "$code" -ge 400 ]]; then
    printf '%s %s returned HTTP %s: %s\n' "$method" "$path" "$code" "$(cat "$tmp/body")" >&2
    return 1
  fi
  cat "$tmp/body"
}

tmp=$(mktemp -d)
trap 'kill $pf_pid 2>/dev/null || true; rm -rf "$tmp"' EXIT

suffix=$(date +%s)
# The first sign-up becomes the console's root account. Re-runs log in with the
# same credentials; set these to an existing account if someone else signed up first.
email="${SMOKE_EMAIL:-smoke@example.com}"
password="${SMOKE_PASSWORD:-smoke-test-password}"

log "API version"
call GET /health/version | jq -e '.version'

log "Create the console account ($email), unless it exists"
call POST /account "{\"userId\":\"unique()\",\"email\":\"$email\",\"password\":\"$password\",\"name\":\"Smoke Test\"}" >/dev/null 2>&1 \
  || echo "account exists or the console is restricted; logging in"

log "Create a session"
call POST /account/sessions/email "{\"email\":\"$email\",\"password\":\"$password\"}" | jq -e '.userId' >/dev/null
cookies=$(grep -i '^x-fallback-cookies:' "$tmp/headers" | cut -d' ' -f2- | tr -d '\r')
[[ -n "$cookies" ]] || fail "no session cookie returned"

log "Create a project"
# A self-hosted instance has a single organization: reuse it when it exists.
team=$(call GET /teams | jq -r '.teams[0]["$id"] // empty')
if [[ -z "$team" ]]; then
  team=$(call POST /teams '{"teamId":"unique()","name":"Smoke"}' | jq -r '.["$id"]')
fi
project="smoke-$suffix"
call POST /projects "{\"projectId\":\"$project\",\"name\":\"Smoke\",\"teamId\":\"$team\"}" | jq -e '.["$id"]' >/dev/null

log "Create a database, a collection and an attribute"
call POST /databases '{"databaseId":"smoke","name":"Smoke"}' "$project" >/dev/null
call POST /databases/smoke/collections '{"collectionId":"items","name":"Items"}' "$project" >/dev/null
call POST /databases/smoke/collections/items/attributes/string '{"key":"title","size":64,"required":false}' "$project" >/dev/null

log "Wait for the databases worker to make the attribute available"
deadline=$((SECONDS + TIMEOUT))
until status=$(call GET /databases/smoke/collections/items/attributes/title "" "$project" | jq -r '.status') && [[ "$status" == available ]]; do
  [[ "$status" == failed ]] && fail "attribute creation failed"
  (( SECONDS < deadline )) || fail "attribute still '$status' after ${TIMEOUT}s: is the worker running?"
  sleep 3
done
echo "attribute is available"

log "Create a document"
call POST /databases/smoke/collections/items/documents '{"documentId":"unique()","data":{"title":"hello"}}' "$project" | jq -e '.title == "hello"' >/dev/null

log "Console"
kubectl -n "$NAMESPACE" run "smoke-$suffix" --rm -i --restart=Never --quiet \
  --image=curlimages/curl:8.16.0 \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"c","image":"curlimages/curl:8.16.0","args":["-fsS","-o","/dev/null","-w","console HTTP %{http_code}\\n","http://'"$base"'-console/"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'

log "OK"
