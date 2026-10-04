# GitOps (Argo CD, Flux)

The chart works with GitOps tools, with two things to set up front:
credentials and how upgrades run migrations.

## Credentials

On `helm install` and `helm upgrade` the chart reads its existing Secret with
`lookup` and reuses the generated values. Tools that render the chart
without cluster access can't do that:

| Tool | `lookup` works? |
| --- | --- |
| `helm install` / `helm upgrade` | yes |
| Flux `HelmRelease` (helm-controller runs Helm) | yes |
| Argo CD (renders with `helm template`) | **no** |
| `helm template` piped to `kubectl apply` | **no** |

Without `lookup`, every render would generate a new `_APP_OPENSSL_KEY_V1`
and new database passwords, making encrypted data unreadable. So with Argo CD
or `helm template`, create the Secrets yourself (External Secrets Operator,
Sealed Secrets, SOPS, ...) and tell the chart not to generate anything:

```yaml
appwrite:
  secrets:
    generate: false
    existingSecret: appwrite-core
postgresql:
  auth:
    existingSecret: appwrite-postgresql
redis:
  auth:
    existingSecret: appwrite-redis
clickhouse:
  auth:
    existingSecret: appwrite-clickhouse
```

With `generate: false`, a missing credential fails the render instead of
producing a random one.

The core Secret needs these keys (names configurable under
`appwrite.secrets.keys`):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: appwrite-core
stringData:
  _APP_OPENSSL_KEY_V1: <64 random characters, never changed>
  _APP_NOTIFICATIONS_TRACKING_SECRET: <random>
  _APP_GEO_SECRET: <random>
```

Generate values with `openssl rand -hex 32`. Keep passwords URL-safe
(letters and digits): Appwrite puts some of them into connection URLs.

## Server-side apply

Helm 4 applies resources with server-side apply by default. Don't edit
chart-managed resources with `kubectl edit`; another field manager owning a
field makes the next upgrade conflict. Change values instead.

## Argo CD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: appwrite
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ghcr.io/levivannoort/charts
    chart: appwrite
    targetRevision: 0.1.0
    helm:
      valuesObject:
        appwrite:
          domain: appwrite.example.com
          certificatesEmail: ops@example.com
          secrets:
            generate: false
            existingSecret: appwrite-core
        # ...
  destination:
    server: https://kubernetes.default.svc
    namespace: appwrite
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

## Flux

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: appwrite
  namespace: flux-system
spec:
  interval: 1h
  url: oci://ghcr.io/levivannoort/charts/appwrite
  ref:
    semver: "0.1.x"
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: appwrite
  namespace: appwrite
spec:
  interval: 1h
  chartRef:
    kind: OCIRepository
    name: appwrite
    namespace: flux-system
  install:
    timeout: 15m
  upgrade:
    timeout: 15m
  values:
    appwrite:
      domain: appwrite.example.com
      certificatesEmail: ops@example.com
```

Flux runs Helm, so generated credentials and upgrade hooks behave as with the
Helm CLI.
