#!/usr/bin/env bash
# Starts an external compute plane next to a kind cluster, as
# docs/executor.md describes for production: S3 (SeaweedFS), the
# open-runtimes orchestrator and executor as Docker containers on the kind
# network. Then writes chart values that point Appwrite at them.
#
# Usage: hack/compute-plane.sh <values-file-to-write> [kind-cluster]
# Requires: docker, kubectl, a Traefik Ingress controller in namespace
# "traefik" (the build containers reach Appwrite through it).
set -euo pipefail

OUT="$1"
CLUSTER="${2:-appwrite}"
NETWORK=kind
FIXTURES="$(cd "$(dirname "$0")/fixtures/compute" && pwd)"
EXECUTOR_SECRET=e2e-executor-secret
ORCHESTRATOR_SECRET=e2e-orchestrator-secret
S3_KEY=appwrite
S3_SECRET=appwrite-s3-secret

ip() { docker inspect "$1" -f "{{(index .NetworkSettings.Networks \"$NETWORK\").IPAddress}}"; }

docker rm -f aw-s3 aw-orchestrator aw-executor >/dev/null 2>&1 || true

echo "==> S3"
docker run -d --name aw-s3 --network "$NETWORK" \
  -v "$FIXTURES/s3.json:/etc/seaweedfs/s3.json:ro" \
  chrislusf/seaweedfs:4.48 server -s3 -s3.config=/etc/seaweedfs/s3.json -dir=/data >/dev/null
for _ in $(seq 1 60); do
  docker run --rm --network "$NETWORK" curlimages/curl:8.16.0 -fsS -o /dev/null \
    --aws-sigv4 "aws:amz:us-east-1:s3" --user "$S3_KEY:$S3_SECRET" -X PUT http://aw-s3:8333/appwrite 2>/dev/null && break
  sleep 2
done

echo "==> Orchestrator"
api_key="$(mktemp)"
printf '%s' "$ORCHESTRATOR_SECRET" > "$api_key"
chmod 644 "$api_key"
docker run -d --name aw-orchestrator --network "$NETWORK" --user 0 \
  -v /var/run/docker.sock:/var/run/docker.sock -v "$api_key:/run/secrets/api-key:ro" \
  -e ORCHESTRATOR_BACKEND=docker -e ORCHESTRATOR_NETWORK="$NETWORK" -e DOCKER_NETWORK="$NETWORK" \
  -e ARTIFACT_ENDPOINT=http://aw-orchestrator:8080 -e API_KEY_FILE=/run/secrets/api-key \
  -e S3_ENDPOINT=http://aw-s3:8333 -e S3_REGION=us-east-1 -e S3_ACCESS_KEY_ID="$S3_KEY" -e S3_SECRET_ACCESS_KEY="$S3_SECRET" \
  ghcr.io/open-runtimes/orchestrator/orchestrator:2.2.2 >/dev/null

echo "==> Executor"
docker run -d --name aw-executor --hostname aw-executor --network "$NETWORK" --stop-signal SIGINT \
  -v /var/run/docker.sock:/var/run/docker.sock -v /tmp:/tmp \
  -e OPR_EXECUTOR_ENV=production -e OPR_EXECUTOR_SECRET="$EXECUTOR_SECRET" -e OPR_EXECUTOR_NETWORK="$NETWORK" \
  -e OPR_EXECUTOR_RUNTIMES=node-22 -e OPR_EXECUTOR_RUNTIME_VERSIONS=v5 -e OPR_EXECUTOR_IMAGES=openruntimes/node:v5-22 \
  -e OPR_EXECUTOR_INACTIVE_THRESHOLD=60 -e OPR_EXECUTOR_MAINTENANCE_INTERVAL=3600 \
  -e "OPR_EXECUTOR_CONNECTION_STORAGE=s3://$S3_KEY:$S3_SECRET@aw-s3:8333?region=us-east-1&insecure=true" \
  openruntimes/executor:0.29.0 >/dev/null
for _ in $(seq 1 60); do
  docker run --rm --network "$NETWORK" curlimages/curl:8.16.0 -fsS -o /dev/null \
    -H "Authorization: Bearer $EXECUTOR_SECRET" http://aw-executor/v1/health 2>/dev/null && break
  sleep 2
done

node_ip=$(ip "$CLUSTER-control-plane")
node_port=$(kubectl -n traefik get svc traefik -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')
# nip.io resolves <ip>.nip.io to <ip>, so build containers can reach Appwrite
# by a hostname that matches appwrite.domain.
domain="$node_ip.nip.io"

cat > "$OUT" <<VALUES
appwrite:
  domain: $domain
  certificatesEmail: ci@example.com
  forceHttps: false
  storage:
    device: s3
    s3:
      endpoint: http://$(ip aw-s3):8333
      region: us-east-1
      bucket: appwrite
      accessKey: $S3_KEY
      secretKey: $S3_SECRET
api:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
ingress:
  enabled: true
compute:
  enabled: true
  executor:
    host: http://$(ip aw-executor)/v1
  orchestrator:
    host: http://$(ip aw-orchestrator):8080
  appwriteEndpoint: http://$domain:$node_port
  functionsRuntimes: [node-22]
  sitesRuntimes: [static-1]
  secrets:
    executorSecret: $EXECUTOR_SECRET
    orchestratorSecret: $ORCHESTRATOR_SECRET
VALUES
echo "==> Wrote $OUT"
