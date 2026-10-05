# Appwrite Helm chart

A Helm chart for running [Appwrite](https://appwrite.io), the open-source
backend platform, on Kubernetes.

```console
helm install appwrite oci://ghcr.io/appwrite-labs/charts/appwrite \
  --namespace appwrite --create-namespace \
  --set appwrite.domain=appwrite.example.com \
  --set appwrite.certificatesEmail=ops@example.com \
  --set ingress.enabled=true \
  --set ingress.tls.enabled=true \
  --set 'ingress.annotations.cert-manager\.io/cluster-issuer=letsencrypt'
```

This assumes an ingress controller and a cert-manager `ClusterIssuer` named
`letsencrypt`. New here? [Getting started](docs/getting-started.md) covers a
local install you can try in ten minutes, and a real one step by step.

| | |
| --- | --- |
| Chart | [`charts/appwrite`](charts/appwrite) ([values and usage](charts/appwrite/README.md)) |
| Appwrite | 2.3.0 |
| Kubernetes | 1.29+ |
| Helm | 4, or 3.18+ |
| Documentation | [`docs/`](docs/README.md) |

## Highlights

- Every Appwrite pod passes the `restricted` Pod Security Standard.
- Built-in PostgreSQL, Redis and ClickHouse, or your own managed services.
- Ingress and Gateway API routes, including function and site previews and
  custom domains.
- Combined, per-queue or grouped workers.
- Functions and Sites: builds run in the cluster as unprivileged Kubernetes
  Jobs in their own namespace; executions run on an executor on a Docker host,
  so no pod gets a Docker socket.
- Credentials generated once and kept; data migrations on upgrade.

## Repository layout

```text
charts/appwrite/   the chart: templates, values, unit tests, CI scenarios
docs/              operator guides
examples/compute/  Docker Compose for the Functions and Sites host
hack/              scripts used by CI and local development
```

## Testing

Every change is checked with chart-testing, `helm lint --strict` on Helm 3.18
and 4, helm-unittest, kubeconform against several Kubernetes versions, and
installs on kind in a namespace that enforces the `restricted` profile:

| Scenario | What it exercises |
| --- | --- |
| `default` | Built-in datastores, combined workers; Kubernetes 1.29 and 1.37 |
| `default`, upgrade from 2.2.0 | Data migration on upgrade |
| `hardened` | NetworkPolicies with restricted egress |
| `separate-workers`, `grouped-workers` | Worker topologies |
| `external-dbs` | PostgreSQL, Redis and ClickHouse outside the release |
| `ingress`, `gateway-api` | Routing through Traefik |
| nightly | Every optional component, S3, and a function built and executed on an external executor |

Each install runs `helm test` and an end-to-end smoke test
([`hack/smoke.sh`](hack/smoke.sh)).

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md).

```console
make tools      # install helm-unittest and helm-values-schema-json
make test       # lint, unit tests, kubeconform, generated-file check
make kind-up install helm-test smoke   # full install on a local kind cluster
```

## License

[BSD 3-Clause](LICENSE).
