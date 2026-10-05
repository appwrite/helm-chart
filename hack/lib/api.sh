#!/usr/bin/env bash
# Helpers for scripts that talk to an installed Appwrite release through a
# port-forward to the API Service. Source this file; it defines:
#   api_connect RELEASE NAMESPACE   start the port-forward
#   api_login                       sign up (if needed) and create a console session
#   call METHOD PATH [JSON] [PROJECT]
#   upload PATH PROJECT FIELD=VALUE...   multipart POST
#   log, fail
# Requires: kubectl, curl, jq.

log() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nFAIL: %s\n' "$*" >&2; exit 1; }

api_connect() {
  local release=$1 namespace=$2
  API_PORT="${API_PORT:-18080}"
  API_SERVICE=$(kubectl -n "$namespace" get svc -l "app.kubernetes.io/instance=$release,app.kubernetes.io/component=api" -o jsonpath='{.items[0].metadata.name}')
  # _APP_MIGRATION_HOST: the one internal host exempt from force-HTTPS.
  API_HOST="$API_SERVICE.$namespace.svc"
  API_TMP=$(mktemp -d)
  kubectl -n "$namespace" port-forward "svc/$API_SERVICE" "$API_PORT:80" >/dev/null 2>&1 &
  API_PF_PID=$!
  trap 'kill $API_PF_PID 2>/dev/null || true; rm -rf "$API_TMP"' EXIT
  for _ in $(seq 1 30); do
    curl -fsS -o /dev/null "http://127.0.0.1:$API_PORT/v1/health/version" -H "Host: $API_HOST" 2>/dev/null && return 0
    sleep 1
  done
  fail "the API isn't reachable through the port-forward"
}

# _request ARGS... -> prints the body; returns 1 on HTTP >= 400
_request() {
  local code
  code=$(curl -sS -D "$API_TMP/headers" -o "$API_TMP/body" -w '%{http_code}' -H "Host: $API_HOST" \
    ${API_COOKIES:+-H "X-Fallback-Cookies: $API_COOKIES"} "$@")
  if [[ "$code" -ge 400 ]]; then
    printf 'HTTP %s: %s\n' "$code" "$(cat "$API_TMP/body")" >&2
    return 1
  fi
  cat "$API_TMP/body"
}

# call METHOD PATH [JSON] [PROJECT]
call() {
  local method=$1 path=$2 data=${3:-} project=${4:-console}
  local args=(-X "$method" "http://127.0.0.1:$API_PORT/v1$path" -H "Content-Type: application/json" -H "X-Appwrite-Project: $project")
  [[ "$project" != console ]] && args+=(-H "X-Appwrite-Mode: admin")
  [[ -n "$data" ]] && args+=(--data "$data")
  _request "${args[@]}"
}

# upload PATH PROJECT FIELD=VALUE... (prefix a value with @ to send a file)
upload() {
  local path=$1 project=$2
  shift 2
  local args=(-X POST "http://127.0.0.1:$API_PORT/v1$path" -H "X-Appwrite-Project: $project" -H "X-Appwrite-Mode: admin")
  local field
  for field in "$@"; do args+=(-F "$field"); done
  _request "${args[@]}"
}

# The first sign-up becomes the console's root account. Re-runs log in with
# the same credentials; set SMOKE_EMAIL and SMOKE_PASSWORD to an existing
# account if someone else signed up first.
api_login() {
  local email="${SMOKE_EMAIL:-smoke@example.com}" password="${SMOKE_PASSWORD:-smoke-test-password}"
  call POST /account "{\"userId\":\"unique()\",\"email\":\"$email\",\"password\":\"$password\",\"name\":\"Smoke Test\"}" >/dev/null 2>&1 \
    || echo "account exists or the console is restricted; logging in"
  call POST /account/sessions/email "{\"email\":\"$email\",\"password\":\"$password\"}" | jq -e '.userId' >/dev/null
  API_COOKIES=$(grep -i '^x-fallback-cookies:' "$API_TMP/headers" | cut -d' ' -f2- | tr -d '\r')
  [[ -n "$API_COOKIES" ]] || fail "no session cookie returned"
}

# api_project NAME -> prints the id of a new project in the instance's organization
api_project() {
  local team project
  project="$1-$(date +%s)"
  team=$(call GET /teams | jq -r '.teams[0]["$id"] // empty')
  if [[ -z "$team" ]]; then
    team=$(call POST /teams '{"teamId":"unique()","name":"Smoke"}' | jq -r '.["$id"]')
  fi
  call POST /projects "{\"projectId\":\"$project\",\"name\":\"$1\",\"teamId\":\"$team\"}" | jq -r '.["$id"]'
}
