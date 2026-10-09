#!/usr/bin/env bash
# Runs Appwrite's own end-to-end tests (PHPUnit, from a checkout of
# appwrite/appwrite) against an installed release.
#
# The tests expect Appwrite's compose stack around them: the API at
# http://appwrite/v1 and on http://localhost, a mail catcher at maildev and
# request catchers at request-catcher-webhook and request-catcher-sms. This
# script
#   1. builds a test image from the checkout at the release's Appwrite version
#      (git archive, so the checkout's working tree is left alone) and loads it
#      into kind,
#   2. starts the catchers in namespace appwrite-e2e, and gives them and the
#      API their compose names in the release namespace,
#   3. upgrades the release with hack/fixtures/appwrite-e2e/values.yaml
#      (development mode, catchers, open console sign-up, no abuse limits, no
#      forced HTTPS, port 80 on the API, runtimes allowed to call the API),
#      which isn't fit for production,
#   4. runs PHPUnit in a pod built from the API's pod template, so it gets the
#      same configuration and credentials, and streams its output.
# Remove what it added with: kubectl delete namespace appwrite-e2e, and
# kubectl -n <namespace> delete svc -l app.kubernetes.io/part-of=appwrite-e2e.
#
# Usage: hack/appwrite-e2e.sh <appwrite-checkout> [release] [namespace] [phpunit args...]
#   hack/appwrite-e2e.sh ~/source/appwrite appwrite appwrite tests/e2e/Services/Account
#   hack/appwrite-e2e.sh ~/source/appwrite appwrite appwrite tests/e2e/Services/Users --filter testCreateUser
# Environment:
#   APPWRITE_REF   git ref to build the tests from (default: the release's Appwrite version)
#   KIND_CLUSTER   kind cluster to load the image into (default: appwrite; empty skips loading)
#   E2E_IMAGE      use this image instead of building one (it must hold tests/ and dev dependencies)
#   E2E_SKIP_UPGRADE=1  don't upgrade the release (it already has the e2e values)
# Requires: docker, kind, kubectl, helm, jq, git. Uses the current kubectl context.
set -euo pipefail

CHECKOUT="${1:?usage: hack/appwrite-e2e.sh <appwrite-checkout> [release] [namespace] [phpunit args...]}"
RELEASE="${2:-appwrite}"
NAMESPACE="${3:-appwrite}"
shift $(( $# < 3 ? $# : 3 ))
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/hack/fixtures/appwrite-e2e"
KIND_CLUSTER="${KIND_CLUSTER-appwrite}"

log() { printf '\n==> %s\n' "$*"; }

selector="app.kubernetes.io/instance=$RELEASE,app.kubernetes.io/component=api"
api=$(kubectl -n "$NAMESPACE" get deploy -l "$selector" -o json | jq '.items[0]')
[[ "$api" != null ]] || { echo "no API Deployment for release $RELEASE in $NAMESPACE" >&2; exit 1; }
version=$(jq -r '.spec.template.spec.containers[0].image | sub(".*:"; "") | sub("@.*"; "")' <<<"$api")
ref="${APPWRITE_REF:-$version}"

# Compose bind-mounts the tests, writable (some write fixtures next to
# themselves); the image needs them inside, owned by www-data (82).
recipe=$(printf 'FROM appwrite-e2e-base:%s\nCOPY --chown=82:82 phpunit.xml /usr/src/code/phpunit.xml\nCOPY --chown=82:82 tests /usr/src/code/tests\nWORKDIR /usr/src/code\n' "$ref")
image="${E2E_IMAGE:-}"
if [[ -z "$image" ]]; then
  # Tagged by the recipe too, so changing it rebuilds the image.
  image="appwrite-e2e:$ref-$(printf '%s' "$recipe" | git hash-object --stdin | cut -c1-7)"
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    log "Build $image from $CHECKOUT at $ref"
    src=$(mktemp -d)
    trap 'rm -rf "$src"' EXIT
    git -C "$CHECKOUT" archive "$ref" | tar -x -C "$src"
    if ! docker image inspect "appwrite-e2e-base:$ref" >/dev/null 2>&1; then
      docker build -q --target development --build-arg TESTING=true --build-arg VERSION="$ref" \
        -t "appwrite-e2e-base:$ref" "$src" >/dev/null
    fi
    printf '%s' "$recipe" | docker build -q -t "$image" -f - "$src" >/dev/null
  fi
  if [[ -n "$KIND_CLUSTER" ]]; then
    log "Load $image into kind cluster $KIND_CLUSTER"
    kind load docker-image "$image" --name "$KIND_CLUSTER" >/dev/null
  fi
fi

log "Catchers, and the API as http://appwrite"
kubectl apply -f "$FIXTURES/catchers.yaml" >/dev/null
kubectl -n "$NAMESPACE" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Service
metadata:
  name: appwrite
  labels: {app.kubernetes.io/part-of: appwrite-e2e}
spec:
  selector:
$(jq -r '.spec.selector.matchLabels | to_entries[] | "    \(.key): \(.value)"' <<<"$api")
  ports:
    - {name: http, port: 80, targetPort: http}
YAML
for name in maildev request-catcher-webhook request-catcher-sms; do
  kubectl -n "$NAMESPACE" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Service
metadata:
  name: $name
  labels: {app.kubernetes.io/part-of: appwrite-e2e}
spec:
  type: ExternalName
  externalName: $name.appwrite-e2e.svc.cluster.local
YAML
done
kubectl -n appwrite-e2e rollout status deploy --timeout=5m >/dev/null

if [[ "${E2E_SKIP_UPGRADE:-}" != 1 ]]; then
  log "Upgrade $RELEASE with the e2e values"
  # Function code calls Appwrite at _APP_DOMAIN, appwrite.test in compose:
  # here the appwrite Service, which runtimes may reach.
  helm upgrade "$RELEASE" "$ROOT/charts/appwrite" -n "$NAMESPACE" --reuse-values \
    -f "$FIXTURES/values.yaml" \
    --set "appwrite.config._APP_DOMAIN=appwrite.$NAMESPACE.svc" \
    --set-json "compute.executor.networkPolicy.extraEgress=$(jq -c --arg ns "$NAMESPACE" \
      '[{to: [{namespaceSelector: {matchLabels: {"kubernetes.io/metadata.name": $ns}}, podSelector: {matchLabels: .spec.selector.matchLabels}}], ports: [{port: 8080}]}]' <<<"$api")" \
    --wait --timeout 15m >/dev/null
fi

log "Run: phpunit $*"
pod="appwrite-e2e-$(date +%s)"
api_service=$(kubectl -n "$NAMESPACE" get svc -l "$selector" -o jsonpath='{.items[0].metadata.name}')
realtime_service=$(kubectl -n "$NAMESPACE" get svc -l "app.kubernetes.io/instance=$RELEASE,app.kubernetes.io/component=realtime" -o jsonpath='{.items[0].metadata.name}')
sed -e "s/API_SERVICE/$api_service/" -e "s/REALTIME_SERVICE/$realtime_service/" "$FIXTURES/proxy.conf" \
  | kubectl -n "$NAMESPACE" create configmap appwrite-e2e-proxy --from-file=nginx.conf=/dev/stdin --dry-run=client -o yaml \
  | kubectl -n "$NAMESPACE" label --local -f - app.kubernetes.io/part-of=appwrite-e2e -o yaml \
  | kubectl -n "$NAMESPACE" apply -f - >/dev/null
# The API's pod template: its env, credentials and security context, without
# probes, ports, init containers or the /storage volume (and the node it pins).
# Tests also call http://localhost and http://appwrite.test, which compose's
# Traefik serves: an nginx sidecar does the same here (proxy.conf).
# Arguments as JSON: jq would read --filter and the like as its own options.
args=$(for a in "$@"; do printf '%s\0' "$a"; done | jq -sR 'split("\u0000") | map(select(. != ""))')
jq --arg pod "$pod" --arg image "$image" --argjson args "$args" '
  .spec.template as $t
  | ($t.spec.containers[0]) as $c
  | {
      apiVersion: "v1", kind: "Pod",
      metadata: {name: $pod, labels: (.spec.selector.matchLabels + {
        "app.kubernetes.io/component": "e2e", "appwrite/datastore-client": "true"})},
      spec: ($t.spec
        | del(.affinity, .topologySpreadConstraints)
        | .restartPolicy = "Never"
        | .securityContext.sysctls = [{name: "net.ipv4.ip_unprivileged_port_start", value: "0"}]
        | .hostAliases = [{ip: "127.0.0.1", hostnames: ["appwrite.test"]}]
        | .initContainers = [($t.spec.containers[0].securityContext) as $sc | {
            name: "proxy", image: "nginxinc/nginx-unprivileged:1.31.6-alpine", restartPolicy: "Always",
            command: ["nginx", "-c", "/etc/nginx-e2e/nginx.conf", "-g", "daemon off;"],
            securityContext: ($sc + {runAsUser: 101, runAsGroup: 101}),
            resources: {requests: {cpu: "10m", memory: "16Mi"}, limits: {memory: "128Mi"}},
            volumeMounts: [{name: "proxy", mountPath: "/etc/nginx-e2e"}, {name: "proxy-tmp", mountPath: "/tmp"}]}]
        | .volumes = [.volumes[] | select(.name == "tmp" or .name == "home")]
            + [{name: "proxy", configMap: {name: "appwrite-e2e-proxy"}}, {name: "proxy-tmp", emptyDir: {}}]
        | .containers = [$c
            | del(.ports, .startupProbe, .readinessProbe, .livenessProbe, .lifecycle)
            | .name = "phpunit" | .image = $image | .imagePullPolicy = "IfNotPresent"
            | .securityContext.readOnlyRootFilesystem = false
            # Empty catchers per run, as in Appwrite CI: some tests reuse
            # addresses and would read mail from an earlier run. Restarting
            # the catchers instead loses mail on open SMTP connections.
            | .command = ["sh", "-c", "curl -fsS -o /dev/null -X DELETE http://maildev:1080/email/all && curl -fsS -o /dev/null http://request-catcher-webhook:5000/__clear__ && curl -fsS -o /dev/null http://request-catcher-sms:5000/__clear__ && exec vendor/bin/phpunit --do-not-cache-result --exclude-group abuseEnabled,screenshots,antivirus,queueRetry \"$@\"", "phpunit"]
            | .args = $args
            | .resources = {requests: {cpu: "100m", memory: "256Mi"}, limits: {memory: "2Gi"}}
            | .volumeMounts = [.volumeMounts[] | select(.name == "tmp" or .name == "home")]])
    }' <<<"$api" | kubectl -n "$NAMESPACE" apply -f - >/dev/null

kubectl -n "$NAMESPACE" wait --for=jsonpath='{.status.phase}'=Running "pod/$pod" --timeout=5m >/dev/null 2>&1 || true
kubectl -n "$NAMESPACE" logs -f "pod/$pod" || true
until phase=$(kubectl -n "$NAMESPACE" get "pod/$pod" -o jsonpath='{.status.phase}') && [[ "$phase" == Succeeded || "$phase" == Failed ]]; do
  sleep 2
done
code=$(kubectl -n "$NAMESPACE" get "pod/$pod" -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}')
kubectl -n "$NAMESPACE" delete "pod/$pod" --wait=false >/dev/null
log "phpunit exited with $code"
exit "$code"
