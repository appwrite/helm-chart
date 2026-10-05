#!/usr/bin/env bash
# Make CoreDNS in a kind cluster on a GitHub runner answer the runner's own
# search domains (*.internal.cloudapp.net) with NXDOMAIN.
#
# kind passes the runner's search domain on to every pod. With ndots:5, a name
# with fewer than five dots (postgres.external-dbs.svc.cluster.local,
# example.com) is first tried with each search domain appended, and CoreDNS
# forwards the runner one upstream. The runner's DNS proxy answers that with
# an error rather than NXDOMAIN, and musl (Alpine images) and Chromium then
# give up on the whole lookup instead of trying the next candidate.
#
# Usage: hack/ci-dns.sh [KIND_CLUSTER]   (default: appwrite)
set -euo pipefail

cluster=${1:-appwrite}
node="${cluster}-control-plane"

domains=$(docker exec "$node" awk '/^search/ {for (i = 2; i <= NF; i++) print $i}' /etc/resolv.conf)
if [ -z "$domains" ]; then
  echo "==> $node has no search domains; nothing to do"
  exit 0
fi

corefile=$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')
for domain in $domains; do
  if grep -q "^${domain}:53 {" <<<"$corefile"; then
    continue
  fi
  echo "==> Answering ${domain} with NXDOMAIN"
  corefile+=$'\n'"${domain}:53 {"$'\n'"    template ANY ANY {"$'\n'"        rcode NXDOMAIN"$'\n'"    }"$'\n'"}"
done

kubectl -n kube-system create configmap coredns --from-literal=Corefile="$corefile" --dry-run=client -o yaml \
  | kubectl apply -f -
kubectl -n kube-system rollout restart deployment/coredns
kubectl -n kube-system rollout status deployment/coredns --timeout=2m
