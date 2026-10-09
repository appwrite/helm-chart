#!/usr/bin/env bash
# End-to-end test for Functions: builds through the orchestrator, executions
# on the executor.
#
# Creates a Node.js function, uploads its code, waits for the orchestrator to
# build it, then executes it through the executor and checks the response.
#
# Usage: hack/functions-smoke.sh [release] [namespace] [runtime]
# FUNCTIONS_EXECUTIONS executes the function that many times (default 1).
# Requires: kubectl, curl, jq, tar.
set -euo pipefail
# shellcheck source=lib/api.sh
source "$(dirname "$0")/lib/api.sh"

RELEASE="${1:-appwrite}"
NAMESPACE="${2:-appwrite}"
RUNTIME="${3:-node-22}"
TIMEOUT="${FUNCTIONS_TIMEOUT:-600}"
EXECUTIONS="${FUNCTIONS_EXECUTIONS:-1}"

api_connect "$RELEASE" "$NAMESPACE"
api_login

log "Create a project and a function ($RUNTIME)"
project=$(api_project functions)
call POST /functions "{\"functionId\":\"hello\",\"name\":\"Hello\",\"runtime\":\"$RUNTIME\",\"execute\":[\"any\"],\"entrypoint\":\"index.js\"}" "$project" >/dev/null

code="$API_TMP/code"
mkdir -p "$code"
cat > "$code/index.js" <<'JS'
module.exports = async ({ res }) => res.json({ hello: 'from kubernetes' });
JS
echo '{"name":"hello","version":"1.0.0","main":"index.js"}' > "$code/package.json"
tar -czf "$API_TMP/code.tar.gz" -C "$code" .

log "Upload a deployment"
deployment=$(upload /functions/hello/deployments "$project" "code=@$API_TMP/code.tar.gz" activate=true | jq -r '.["$id"]')
echo "$deployment"

log "Wait for the build"
deadline=$((SECONDS + TIMEOUT))
until status=$(call GET "/functions/hello/deployments/$deployment" "" "$project" | jq -r '.status') && [[ "$status" == ready ]]; do
  if [[ "$status" == failed ]]; then
    call GET "/functions/hello/deployments/$deployment" "" "$project" | jq -r '.buildLogs' >&2
    fail "build failed"
  fi
  (( SECONDS < deadline )) || fail "deployment still '$status' after ${TIMEOUT}s"
  sleep 5
done
echo "deployment is ready"

# Several executions reach several executor replicas, each starting its own runtime.
for i in $(seq 1 "$EXECUTIONS"); do
  log "Execute ($i/$EXECUTIONS)"
  response=$(call POST /functions/hello/executions '{"async":false}' "$project")
  jq '{status, responseStatusCode, responseBody, duration}' <<<"$response"
  jq -e '.responseStatusCode == 200 and (.responseBody | fromjson | .hello == "from kubernetes")' <<<"$response" >/dev/null \
    || fail "unexpected execution result"
done

log "OK"
