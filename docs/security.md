# Security

## Pod Security Standards

Every pod the chart runs passes the Kubernetes
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
| ServiceAccount token | not mounted |

| Component | User | Notes |
| --- | --- | --- |
| Appwrite (API, realtime, workers, tasks) | `www-data` (82) | API and realtime listen on 8080 (`PORT`). `/tmp`, `/storage/cache` and certbot's directories are `emptyDir`s. |
| Console | `bun` (1000) | |
| Geo | `www-data` (82) | Its port 80 is hard-coded, so the pod sets the namespaced sysctl `net.ipv4.ip_unprivileged_port_start=0`, which `restricted` allows. |
| PostgreSQL | `postgres` (999) | `/var/run/postgresql` is an `emptyDir`. |
| Redis | `redis` (999) | |
| ClickHouse | `clickhouse` (101) | Users and logging come from mounted files, because the image's entrypoint would otherwise write them to `/etc`. Logs go to stdout. |

Every security context is a value you can override per component
(`<component>.podSecurityContext`, `<component>.containerSecurityContext`). For
the Appwrite image, `podSecurityContext` and `containerSecurityContext` at the
top level apply to every component that doesn't set its own.

### Functions and Sites

Appwrite runs functions and sites with the
[open-runtimes executor](https://github.com/open-runtimes/executor), which needs
a Docker daemon. Mounting a node's Docker socket, or running Docker-in-Docker,
gives that pod root on the node, so the chart doesn't do either. Run the
executor on a separate Docker host and point the chart at it; see
[executor.md](executor.md).

## Credentials

The chart keeps credentials in a Secret named after the release:

| Key | Used for |
| --- | --- |
| `_APP_OPENSSL_KEY_V1` | Encrypting data at rest and signing JWTs. Losing it makes encrypted data unreadable. |
| `_APP_NOTIFICATIONS_TRACKING_SECRET` | Signing email tracking links. |
| `_APP_GEO_SECRET` | Authenticating Appwrite to the geo service. |
| `postgres-password`, `redis-password`, `clickhouse-password` | Built-in datastores. |

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

## Network policies

`networkPolicy.enabled: true` creates policies that only take effect with a
CNI that enforces them (Calico, Cilium, kindnet, and most managed offerings).

| Policy | Selects | Allows in |
| --- | --- | --- |
| `<release>-edge` | API, console, realtime | `networkPolicy.ingress.from` (any source when empty) on the HTTP port, and every pod of the release |
| `<release>-internal` | geo | pods of the release |
| `<release>-datastores` | PostgreSQL, Redis, ClickHouse | Appwrite pods of the release (label `appwrite/datastore-client: "true"`) |
| `<release>-background` | workers and tasks | nothing |

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
cosign verify ghcr.io/levivannoort/charts/appwrite:<version> \
  --certificate-identity-regexp '^https://github.com/levivannoort/helm-chart/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

gh attestation verify oci://ghcr.io/levivannoort/charts/appwrite:<version> \
  --owner levivannoort
```
