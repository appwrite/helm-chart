#!/usr/bin/env bash
# End-to-end smoke test for an installed Appwrite release.
#
# Signs in to the console (creating the root account on a fresh install),
# creates a project, a database, a collection and an attribute, and waits for
# the attribute to become available. Attributes are created asynchronously by
# the databases queue, so this proves the API, datastores and workers work
# together. Finally it checks the console.
#
# Usage: hack/smoke.sh [release] [namespace]
# Requires: kubectl, curl, jq.
set -euo pipefail
# shellcheck source=lib/api.sh
source "$(dirname "$0")/lib/api.sh"

RELEASE="${1:-appwrite}"
NAMESPACE="${2:-appwrite}"
TIMEOUT="${SMOKE_TIMEOUT:-180}"

api_connect "$RELEASE" "$NAMESPACE"

log "API version"
call GET /health/version | jq -e '.version'

log "Sign in to the console"
api_login

log "Create a project"
project=$(api_project smoke)
echo "$project"

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
console="${API_SERVICE%-api}-console"
kubectl -n "$NAMESPACE" run "smoke-$(date +%s)" --rm -i --restart=Never --quiet \
  --image=curlimages/curl:8.16.0 \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"c","image":"curlimages/curl:8.16.0","args":["-fsS","-o","/dev/null","-w","console HTTP %{http_code}\\n","http://'"$console"'/"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'

log "OK"
