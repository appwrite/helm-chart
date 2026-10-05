# Security

## Pod Security Standards

Every pod in the Appwrite namespace passes the Kubernetes
[`restricted` Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted),
and CI installs the chart into a namespace that enforces it. You can do the same:

```console
kubectl create namespace appwrite
kubectl label namespace appwrite \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted
```

What that means for each pod:

| Setting | Value |
| --- | --- |
| `runAsNonRoot` | `true` |
| `allowPrivilegeEscalation` | `false` |
| `capabilities` | drop `ALL` |
| `seccompProfile` | `RuntimeDefault` |
| `readOnlyRootFilesystem` | `true`; writable paths are `emptyDir` volumes |
| ServiceAccount token | not mounted, except for the orchestrator (`compute.enabled`) |

| Component | User | Notes |
| --- | --- | --- |
| Appwrite (API, realtime, workers, tasks) | `www-data` (82) | API and realtime listen on 8080 (`PORT`). `/tmp`, `/storage/cache` and certbot's directories are `emptyDir`s. |
| Console | `bun` (1000) | |
| Geo | `www-data` (82) | Its port 80 is hard-coded, so the pod sets the namespaced sysctl `net.ipv4.ip_unprivileged_port_start=0`, which `restricted` allows. |
| PostgreSQL | `postgres` (999) | `/var/run/postgresql` is an `emptyDir`. |
| Redis | `redis` (999) | |
| ClickHouse | `clickhouse` (101) | Users and logging come from mounted files, because the image's entrypoint would otherwise write them to `/etc`. Logs go to stdout. |
| Browser | 999 | `/dev/shm` is a memory `emptyDir`. |
| Assistant | 1000 | |
| Autogravity | 65532 | |
| Embedding | 10001 | Models are kept on their own PersistentVolumeClaim. |
| Orchestrator | `nonroot` (65532) | The only pod with a ServiceAccount token, for its Role in the build namespace. |

Every security context is a value you can override per component
(`<component>.podSecurityContext`, `<component>.containerSecurityContext`). For
the Appwrite image, `podSecurityContext` and `containerSecurityContext` at the
top level apply to every component that doesn't set its own.

### Functions and Sites

Builds run user-supplied build commands, possibly as root, so they can't
pass `restricted`. The chart runs them in a namespace of their own under
`baseline`, which still forbids privileged pods and host access, without
ServiceAccount tokens and behind a NetworkPolicy.

Executions need a Docker daemon: the
[open-runtimes executor](https://github.com/open-runtimes/executor) starts a
container per runtime. Mounting a node's Docker socket, or running
Docker-in-Docker, gives that pod root on the node, so the chart runs neither.
The executor runs on a separate Docker host; see [executor.md](executor.md).

## Credentials

The chart keeps credentials in a Secret named after the release:

| Key | Used for |
| --- | --- |
| `_APP_OPENSSL_KEY_V1` | Encrypting data at rest and signing JWTs. Losing it makes encrypted data unreadable. |
| `_APP_NOTIFICATIONS_TRACKING_SECRET` | Signing email tracking links. |
| `_APP_GEO_SECRET` | Authenticating Appwrite to the geo service. |
| `postgres-password`, `redis-password`, `clickhouse-password` | Built-in datastores, or an external Redis or ClickHouse with an inline password. |
| `db-password`, `documentsdb-password`, `vectorsdb-password` | External databases with an inline password. |
| `executor-secret`, `orchestrator-secret` | The executor and the orchestrator (`compute.enabled`). |
| `s3-access-key`, `s3-secret-key` | S3 storage with inline keys. |
| `smtp-password`, `openai-api-key` | SMTP and the assistant, when set inline. |

Values you set inline (`password: ...`) are stored in this Secret too. Only
the first group is generated; the rest exist when the matching feature is on
and has no `existingSecret`.

Missing values are generated on install and reused on every upgrade: the chart
reads the existing Secret back with `lookup`. The Secret has
`helm.sh/resource-policy: keep`, so it survives `helm uninstall`, together with
the data it protects. The chart refuses to:

- generate a new `_APP_OPENSSL_KEY_V1` during an upgrade (the Secret is missing),
- change `_APP_OPENSSL_KEY_V1` to a different explicit value, unless
  `appwrite.secrets.allowKeyRotation` is `true`.

**Back up `_APP_OPENSSL_KEY_V1`.**

```console
kubectl -n appwrite get secret appwrite -o jsonpath='{.data._APP_OPENSSL_KEY_V1}' | base64 -d
```

### Bringing your own Secrets

Point each group of credentials at a Secret you manage, for example with
External Secrets, Sealed Secrets or SOPS:

```yaml
appwrite:
  secrets:
    existingSecret: appwrite-core          # keys: _APP_OPENSSL_KEY_V1, _APP_NOTIFICATIONS_TRACKING_SECRET, _APP_GEO_SECRET
    generate: false                        # fail instead of generating anything
postgresql:
  auth:
    existingSecret: appwrite-postgresql    # key: postgres-password
redis:
  auth:
    existingSecret: appwrite-redis         # key: redis-password
clickhouse:
  auth:
    existingSecret: appwrite-clickhouse    # key: clickhouse-password
```

Key names are configurable (`appwrite.secrets.keys.*`, `*.auth.passwordKey`).

> [!IMPORTANT]
> Tools that render templates without cluster access (Argo CD, `helm template`)
> can't read the existing Secret, so generated values would change on every
> render. Use existing Secrets and `appwrite.secrets.generate: false` with them;
> see [gitops.md](gitops.md).

## Rotating credentials

| Credential | How |
| --- | --- |
| `_APP_OPENSSL_KEY_V1` | Don't. Appwrite can't re-encrypt existing data with a new key. |
| `_APP_NOTIFICATIONS_TRACKING_SECRET`, `_APP_GEO_SECRET` | Change the value in the Secret (or `appwrite.secrets.*`) and upgrade. |
| Built-in PostgreSQL password | PostgreSQL only reads `POSTGRES_PASSWORD` when it creates the database. Change the password in PostgreSQL first (`ALTER USER appwrite PASSWORD '...'`), then in the Secret, then upgrade. |
| Built-in Redis and ClickHouse passwords | Change the value and upgrade; both read it on every start. |
| External services, executor and orchestrator | Change it on the service and in the Secret, then upgrade or restart the Appwrite pods. |

Pods restart on their own when the chart's Secret changes through
`helm upgrade`. When you change a Secret you manage, restart them:
`kubectl -n appwrite rollout restart deployment -l app.kubernetes.io/instance=appwrite`.

For the same reason, don't delete the chart's Secret while keeping the
PostgreSQL volume: a new install would generate a password the existing
database doesn't accept.

## Network policies

`networkPolicy.enabled: true` creates policies that only take effect with a
CNI that enforces them (Calico, Cilium, kindnet, and most managed offerings).

| Policy | Selects | Allows in |
| --- | --- | --- |
| `<fullname>-edge` | API, console, realtime | `networkPolicy.ingress.from` (any source when empty) on the HTTP port, and every pod of the release |
| `<fullname>-internal` | geo, browser, assistant, autogravity, embedding | pods of the release |
| `<fullname>-datastores` | PostgreSQL, Redis, ClickHouse | Appwrite pods of the release (label `appwrite/datastore-client: "true"`) |
| `<fullname>-background` | workers and tasks | nothing |
| `<fullname>-mqtt` | MQTT broker (`mqtt.enabled`) | any source, on the MQTT ports |
| `<fullname>-orchestrator` | orchestrator (`compute.enabled`) | pods of the release and build pods |

With in-cluster builds, `<fullname>-edge` also admits build pods to the API.
Build pods get their own policy in the build namespace, `<fullname>-build`,
on by default (`compute.builds.networkPolicy.enabled`); see
[executor.md](executor.md#isolation).

Two more limit outgoing traffic:

| Policy | Selects | Allows out |
| --- | --- | --- |
| `<fullname>-browser-egress` | browser (`browser.enabled`) | DNS, the API, and public IP addresses (private, link-local and CGNAT ranges are blocked) |
| `<fullname>-egress` | every pod of the release (`networkPolicy.egress.enabled`) | DNS, pods of the release, `networkPolicy.egress.extraRules` |

Policies add up: with `egress.enabled`, the browser may also reach the other
pods of the release.

Restrict the entry points to your ingress controller or Gateway:

```yaml
networkPolicy:
  enabled: true
  ingress:
    from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: traefik
```

### Egress

Egress is open by default, because Appwrite talks to many external services:
webhooks, SMTP, OAuth and VCS providers, external databases, S3 and the
executor. `networkPolicy.egress.enabled: true` limits every pod to DNS and the
release itself; add what your installation needs with `extraRules`:

```yaml
networkPolicy:
  enabled: true
  egress:
    enabled: true
    extraRules:
      # SMTP
      - to:
          - ipBlock:
              cidr: 0.0.0.0/0
        ports:
          - port: 587
      # External PostgreSQL
      - to:
          - ipBlock:
              cidr: 10.20.0.0/16
        ports:
          - port: 5432
```

## Verifying chart signatures

Released charts are signed with [cosign](https://github.com/sigstore/cosign)
keyless signing from GitHub Actions, and carry a build provenance attestation:

```console
cosign verify ghcr.io/appwrite/charts/appwrite:<version> \
  --certificate-identity https://github.com/appwrite/helm-chart/.github/workflows/release.yaml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

gh attestation verify oci://ghcr.io/appwrite/charts/appwrite:<version> \
  --repo appwrite/helm-chart
```
