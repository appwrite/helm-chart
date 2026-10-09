# Appwrite Helm chart

A Helm chart for running [Appwrite](https://appwrite.io), the open-source
backend platform, on Kubernetes: authentication, databases, storage,
functions, sites, messaging and realtime, on your own cluster.

| | |
| --- | --- |
| Appwrite | 2.3.0 |
| Kubernetes | 1.29+ |
| Helm | 4, or 3.18+ |
| Chart | `oci://ghcr.io/appwrite/charts/appwrite` ([values](charts/appwrite/README.md#values)) |

## Quick start

With an ingress controller and a cert-manager `ClusterIssuer` named
`letsencrypt`:

```console
helm install appwrite oci://ghcr.io/appwrite/charts/appwrite \
  --namespace appwrite --create-namespace \
  --set appwrite.domain=appwrite.example.com \
  --set appwrite.certificatesEmail=ops@example.com \
  --set ingress.enabled=true \
  --set ingress.tls.enabled=true \
  --set 'ingress.annotations.cert-manager\.io/cluster-issuer=letsencrypt' \
  --set ingress.wildcard.enabled=false \
  --wait --timeout 15m
```

Open `https://appwrite.example.com` and sign up: the first account becomes
the console administrator. Then back up the encryption key the chart
generated, which you need to read a database backup:

```console
kubectl -n appwrite get secret appwrite -o jsonpath='{.data._APP_OPENSSL_KEY_V1}' | base64 -d
```

## Pick your path

| I want to... | Start here |
| --- | --- |
| Try Appwrite on my laptop in ten minutes | [Getting started: local](docs/getting-started.md#try-it-on-your-machine), [`examples/local.yaml`](examples/local.yaml) |
| Install it on a cluster with my own domain | [Getting started: real cluster](docs/getting-started.md#install-on-a-real-cluster), [`examples/minimal.yaml`](examples/minimal.yaml) |
| Use managed databases, S3 and SMTP | [External databases](docs/external-databases.md), [`examples/external-services.yaml`](examples/external-services.yaml) |
| Run it on AWS | [`examples/aws.yaml`](examples/aws.yaml) |
| Go to production | [Production checklist](docs/production.md), [`examples/production.yaml`](examples/production.yaml) |
| Run Functions and Sites | [Functions and Sites](docs/executor.md), [`examples/functions.yaml`](examples/functions.yaml) |
| Move from Docker Compose | [Migrating from Docker](docs/migrating-from-docker.md) |

All guides: [`docs/`](docs/README.md).

## Built in, or bring your own

Out of the box the chart runs everything Appwrite needs, so a plain install
works with no outside services. Each piece can be replaced on its own:

| Service | By default | Bring your own | Guide |
| --- | --- | --- | --- |
| PostgreSQL | built-in StatefulSet | RDS, Cloud SQL, Azure, CloudNativePG; or MariaDB, MySQL, MongoDB | [External databases](docs/external-databases.md#postgresql) |
| Redis | built-in StatefulSet | ElastiCache, Memorystore, Azure Cache, Valkey | [External databases](docs/external-databases.md#redis) |
| ClickHouse | built-in StatefulSet | ClickHouse Cloud, Altinity operator | [External databases](docs/external-databases.md#clickhouse) |
| File storage | PersistentVolumeClaim | S3, R2, GCS, Spaces, MinIO, ... | [Storage](docs/storage.md#s3) |
| Email | off | any SMTP server | [Integrations](docs/integrations.md#email-smtp) |
| Git deployments, OAuth, SMS, Sentry | off | GitHub, GitLab, Gitea, Bitbucket, Twilio, ... | [Integrations](docs/integrations.md) |

The built-in datastores are single replicas, fine for trying Appwrite and for
small installs. Use replicated services in production.

## Highlights

- Every Appwrite pod passes the `restricted` Pod Security Standard.
- Ingress and Gateway API routes, including function and site previews and
  custom domains.
- Combined, per-queue or grouped workers.
- Functions and Sites in the cluster: builds run as unprivileged Kubernetes
  Jobs in their own namespace; executions run on an executor with its own
  Docker-in-Docker daemon, in a namespace of its own (privileged, opt-in).
- Credentials generated once and kept; data migrations on upgrade; guards
  against changing the encryption key or downgrading.
- Signed releases with provenance ([verifying](docs/security.md#verifying-chart-signatures)).

## Repository layout

```text
charts/appwrite/   the chart: templates, values, unit tests, CI scenarios
docs/              operator guides
examples/          values files to start from
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
| nightly | Every optional component, S3, and a function built and executed in the cluster |

Each install runs `helm test` and an end-to-end smoke test
([`hack/smoke.sh`](hack/smoke.sh)). The files in [`examples/`](examples) are
rendered and validated on every change.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: [SECURITY.md](SECURITY.md).

```console
make tools      # install helm-unittest and helm-values-schema-json
make test       # lint, unit tests, kubeconform, examples, generated-file check
make kind-up install helm-test smoke   # full install on a local kind cluster
```

## License

[BSD 3-Clause](LICENSE).
