#!/usr/bin/env bash
# Creates the Secrets the external-dbs scenario references in the Appwrite
# namespace, with the passwords from hack/fixtures/external-dbs.yaml.
set -euo pipefail
NAMESPACE="${1:-appwrite}"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" create secret generic external-datastores \
  --from-literal=db-password=external-pg-password \
  --from-literal=redis-password=external-redis-password \
  --from-literal=clickhouse-password=externalClickhousePassword \
  --dry-run=client -o yaml | kubectl apply -f -
