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
compute:                                   # with Functions and Sites
  secrets:
    existingSecret: appwrite-compute
```

With `generate: false`, a missing credential fails the render instead of
producing a random one, for example `No value for postgres-password`.

| Secret | Keys (configurable) |
| --- | --- |
| `appwrite.secrets.existingSecret` | `_APP_OPENSSL_KEY_V1`, `_APP_NOTIFICATIONS_TRACKING_SECRET`, `_APP_GEO_SECRET` (`appwrite.secrets.keys.*`) |
| `postgresql.auth.existingSecret` | `postgres-password` (`postgresql.auth.passwordKey`) |
| `redis.auth.existingSecret` | `redis-password` (`redis.auth.passwordKey`) |
| `clickhouse.auth.existingSecret` | `clickhouse-password` (`clickhouse.auth.passwordKey`) |
| `compute.secrets.existingSecret` | `executor-secret`, `orchestrator-secret` (`compute.secrets.*Key`) |
| `appwrite.storage.s3.existingSecret` | `s3-access-key`, `s3-secret-key` (`appwrite.storage.s3.accessKeyKey`, `secretKeyKey`) |

The core Secret needs these keys (names configurable under
`appwrite.secrets.keys`):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: appwrite-core
stringData:
  _APP_OPENSSL_KEY_V1: <random, never changed>
  _APP_NOTIFICATIONS_TRACKING_SECRET: <random>
  _APP_GEO_SECRET: <random>
```

Generate values with `openssl rand -hex 32` (the chart itself generates 48
random letters and digits). Keep passwords URL-safe (letters and digits):
Appwrite puts some of them into connection URLs.

## Server-side apply

Helm 4 applies resources with server-side apply by default. Don't edit
chart-managed resources with `kubectl edit`; another field manager owning a
field makes the next upgrade conflict. Change values instead.

## Migrations

When the Appwrite version changes, its data migration has to run once
([upgrading.md](upgrading.md)). With the Helm CLI and Flux, a post-upgrade
hook does that. Argo CD renders the chart with `helm template`, which never
looks like an upgrade, so the hook doesn't run there. With Argo CD, set
`migrations.mode: job`: the chart then renders a plain Job instead
([upgrading.md](upgrading.md#gitops)).

The Job's name holds the Appwrite version and a short hash of its spec. A
Job's pod template can't be changed, so a new name is what lets Argo CD sync
when the spec changes:

- A chart upgrade that leaves the Job's spec alone keeps the same Job, and
  nothing runs again.
- Changing the Job's spec (a new Appwrite version, but also its resources,
  environment or scheduling) creates a new Job, which runs the migration
  again. Appwrite's migration is idempotent, so that's safe, if slow on a
  large database.
- Deleting the current Job while auto-sync is on makes Argo CD recreate it,
  which also runs the migration again. Delete Jobs of older versions
  whenever you like.

Two checks rely on `lookup` and so do nothing under Argo CD: the guard
against downgrading Appwrite (`migrations.allowDowngrade`), and the retry of
a failed hook migration.

## Argo CD

Charts on GHCR are OCI artifacts, so register the registry with Argo CD
first:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: appwrite-charts
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: helm
  name: appwrite-charts
  url: ghcr.io/appwrite/charts
  enableOCI: "true"
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: appwrite
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ghcr.io/appwrite/charts
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
          storage:
            device: s3
            s3:
              endpoint: https://s3.example.com
              bucket: appwrite
              existingSecret: appwrite-s3
        postgresql:
          auth:
            existingSecret: appwrite-postgresql
        redis:
          auth:
            existingSecret: appwrite-redis
        clickhouse:
          auth:
            existingSecret: appwrite-clickhouse
        persistence:
          annotations:
            argocd.argoproj.io/sync-options: Prune=false,Delete=false
        migrations:
          mode: job
        # ...
  destination:
    server: https://kubernetes.default.svc
    namespace: appwrite
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

Things that differ from the Helm CLI:

- **Kept resources.** Argo CD ignores `helm.sh/resource-policy: keep`, so
  deleting the Application (or pruning) deletes the `/storage` claim. The
  `Prune=false,Delete=false` sync option above keeps it. The datastores'
  claims belong to their StatefulSets and Argo CD leaves them alone. If the
  chart's own Secret holds anything (it doesn't with `generate: false` and
  existing Secrets for everything), back it up before deleting the
  Application.
- **The build namespace.** With Functions and Sites, the chart creates a
  cluster-scoped Namespace, `<release namespace>-builds`, plus a Role and a
  NetworkPolicy in it. A restricted AppProject must allow the `Namespace` kind
  in `clusterResourceWhitelist` and the build namespace in `destinations`.
  Or create the namespace yourself and set
  `compute.builds.createNamespace: false`
  ([executor.md](executor.md#who-creates-the-build-namespace)).

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: appwrite
  namespace: argocd
spec:
  sourceRepos: [ghcr.io/appwrite/charts]
  destinations:
    - {server: https://kubernetes.default.svc, namespace: appwrite}
    - {server: https://kubernetes.default.svc, namespace: appwrite-builds}
  clusterResourceWhitelist:
    - {group: "", kind: Namespace}
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
  url: oci://ghcr.io/appwrite/charts/appwrite
  ref:
    semver: "0.1.x"
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
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
    timeout: 2h    # covers the data migration on Appwrite version changes
  values:
    appwrite:
      domain: appwrite.example.com
      certificatesEmail: ops@example.com
```

Flux runs Helm, so generated credentials and upgrade hooks behave as with the
Helm CLI.

To have Flux check the chart's signature, add `verify` to the
`OCIRepository`. The chart is signed with cosign 3, so this needs a Flux
release that verifies cosign 3 bundles:

```yaml
spec:
  verify:
    provider: cosign
    matchOIDCIdentity:
      - issuer: ^https://token\.actions\.githubusercontent\.com$
        subject: ^https://github\.com/appwrite/helm-chart/\.github/workflows/release\.yaml@refs/heads/main$
```
