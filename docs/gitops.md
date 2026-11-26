# GitOps (Argo CD, Flux)

The chart works with GitOps tools. Two things need setting up front:
credentials, and how upgrades run Appwrite's data migration.

| | Credentials | Migrations |
| --- | --- | --- |
| Flux `HelmRelease` | generated, or your own Secrets | `migrations.mode: hook` (default) |
| Argo CD | **your own Secrets, `generate: false`** | **`migrations.mode: job`** |
| `helm template`, Kustomize `helmCharts`, anything else that renders without Helm | **your own Secrets, `generate: false`** | `job`, or `none` and run it yourself |

> [!WARNING]
> **Argo CD with default values destroys data.** By default the chart
> generates the encryption key (`_APP_OPENSSL_KEY_V1`) and the datastore
> passwords, and reads them back from the cluster on every `helm upgrade`.
> Argo CD renders the chart with `helm template`, which can't read the
> cluster, so every render generates new values: Argo CD overwrites the
> chart's Secret and restarts the Appwrite pods, encrypted data becomes
> unreadable, and Appwrite can no longer log in to the built-in datastores.
> The chart's guard against this only fires during `helm upgrade`, never
> under Argo CD.
>
> Before the first sync, create the Secrets yourself and set:
>
> ```yaml
> appwrite:
>   secrets:
>     generate: false                  # fail the render instead of generating anything
>     existingSecret: appwrite-credentials
> database:
>   password:
>     secretName: appwrite-credentials
> redis:
>   password:
>     secretName: appwrite-credentials
> clickhouse:
>   password:
>     secretName: appwrite-credentials
> storage:
>   s3:                                # the built-in object storage's keys too
>     accessKeyId:
>       secretName: appwrite-credentials
>     secretAccessKey:
>       secretName: appwrite-credentials
> compute:
>   secrets:
>     existingSecret: appwrite-credentials
>   executor:
>     existingSecret: appwrite-executor  # a copy in the executor namespace
> migrations:
>   mode: job
> ```
>
> Functions and Sites are on by default, so the executor needs
> [its own copy](#what-goes-in-the-secrets) of its secret and the S3 keys, in
> its namespace. Without Functions and Sites, set `compute.enabled: false`
> and leave out the `compute` block. [Credentials](#credentials) has the
> details.

## Credentials

On `helm install` and `helm upgrade` the chart reads its existing Secret with
`lookup` and reuses the values it generated before. Tools that render the
chart without cluster access get nothing back from `lookup`:

| Tool | `lookup` works? |
| --- | --- |
| `helm install`, `helm upgrade` | yes |
| Flux `HelmRelease` (helm-controller runs Helm) | yes |
| Argo CD (renders with `helm template`) | **no** |
| `helm template` piped to `kubectl apply` | **no** |

Without `lookup`, every render generates a new `_APP_OPENSSL_KEY_V1` and new
passwords. So with Argo CD or `helm template`, keep every credential in a
Secret you manage (External Secrets Operator, Sealed Secrets, SOPS, ...) and
set `appwrite.secrets.generate: false`. A missing credential then fails the
render instead of producing a random one:

```text
No value for _APP_GEO_SECRET: provide it explicitly or through an existing Secret (appwrite.secrets.generate is false).
```

With Flux you can keep the defaults, or use your own Secrets the same way.

Explicit values (`appwrite.secrets.opensslKey`, `*.password.value`, ...) also
render the same every time, but they end up in Git in plain text.

### What goes in the Secrets

One Secret can hold every key, as in the warning above, or each block can
have its own. The key names below are the defaults; each has a value to
change it.

| Value | Keys | Needed when |
| --- | --- | --- |
| `appwrite.secrets.existingSecret` | `_APP_OPENSSL_KEY_V1`, `_APP_NOTIFICATIONS_TRACKING_SECRET`, `_APP_GEO_SECRET` (`appwrite.secrets.keys.*`) | always |
| `database.password.secretName` | `db-password` (`database.password.secretKey`) | always: generated for the built-in PostgreSQL, required for an external database |
| `redis.password.secretName` | `redis-password` (`redis.password.secretKey`) | built-in Redis with `redis.builtin.requirePassword` (the default), or an external Redis with a password |
| `clickhouse.password.secretName` | `clickhouse-password` (`clickhouse.password.secretKey`) | built-in ClickHouse, or an external one with a password |
| `compute.secrets.existingSecret` | `executor-secret`, `orchestrator-secret` (`compute.secrets.executorSecretKey`, `orchestratorSecretKey`) | `compute.enabled`, the default |
| `compute.executor.existingSecret`, **in the executor namespace** | `executor-secret`, `s3-access-key`, `s3-secret-key` ([executor.md](executor.md#existing-secrets)) | `compute.enabled`, the default, with `compute.secrets.existingSecret` or an S3 `secretName` |
| `storage.s3.accessKeyId.secretName`, `storage.s3.secretAccessKey.secretName` | `s3-access-key`, `s3-secret-key` (their `secretKey`) | `storage.device: s3`, the default: for the built-in object storage too, whose keys the chart would otherwise generate |
| `documentsDb.password.secretName`, `vectorsDb.password.secretName` | `documentsdb-password`, `vectorsdb-password` (their `secretKey`) | DocumentsDB or VectorsDB with a password other than the main database's |
| `smtp.password.secretName` | `smtp-password` (`smtp.password.secretKey`) | SMTP with a password |

The executor runs in a namespace of its own and can't read Secrets in the
release namespace, so it needs its own copy of `executor-secret` and the S3
keys. The values must match those in the release namespace.
[`examples/functions-existing-secrets.yaml`](../examples/functions-existing-secrets.yaml)
shows the compute values with Secrets you manage.

Generate each value once, for example with `openssl rand -hex 32` (the chart
itself generates 48 letters and digits), and never change
`_APP_OPENSSL_KEY_V1`: Appwrite can't re-encrypt data with a new key. Keep
passwords URL-safe (letters and digits): Appwrite puts the ClickHouse
password into a connection URL unencoded. For Sealed Secrets or SOPS, write
the Secret to a file and seal or encrypt that:

```console
kubectl -n appwrite create secret generic appwrite-credentials --dry-run=client -o yaml \
  --from-literal=_APP_OPENSSL_KEY_V1="$(openssl rand -hex 32)" \
  --from-literal=_APP_NOTIFICATIONS_TRACKING_SECRET="$(openssl rand -hex 32)" \
  --from-literal=_APP_GEO_SECRET="$(openssl rand -hex 32)" \
  --from-literal=db-password="$(openssl rand -hex 32)" \
  --from-literal=redis-password="$(openssl rand -hex 32)" \
  --from-literal=clickhouse-password="$(openssl rand -hex 32)" \
  > appwrite-credentials.yaml
```

Don't commit that file before it's sealed or encrypted, and keep a copy of
the values outside the cluster
([backup-restore.md](backup-restore.md#credentials)).

When moving an existing install to GitOps, reuse the values in the chart's
Secret instead of generating new ones. Its keys have the default names, so
its `data` can be copied as it is. A release last upgraded before the
chart's values were regrouped still holds the PostgreSQL password as
`postgres-password`: rename that key to `db-password`.

```console
kubectl -n appwrite get secret appwrite -o yaml
```

### External Secrets Operator

With the [External Secrets Operator](https://external-secrets.io), the
values can live in AWS Secrets Manager, Google Secret Manager, Vault or Azure
Key Vault. This example reads one JSON secret, `appwrite/production`, whose
properties are named after the keys above, through a `ClusterSecretStore`
(a namespaced `SecretStore` can't serve both namespaces):

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: appwrite-credentials
  namespace: appwrite
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-secrets-manager              # a store you've set up
  target:
    name: appwrite-credentials             # what existingSecret and secretName name
    creationPolicy: Owner
    deletionPolicy: Retain                 # keep the Secret if the source disappears
  dataFrom:
    - extract:
        key: appwrite/production           # every property becomes a key
---
# Only with Functions and Sites (compute.executor.existingSecret).
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: appwrite-executor-credentials
  namespace: appwrite-executor
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-secrets-manager
  target:
    name: appwrite-executor-credentials
    creationPolicy: Owner
    deletionPolicy: Retain
  data:
    - secretKey: executor-secret
      remoteRef: {key: appwrite/production, property: executor-secret}
    - secretKey: s3-access-key
      remoteRef: {key: appwrite/production, property: s3-access-key}
    - secretKey: s3-secret-key
      remoteRef: {key: appwrite/production, property: s3-secret-key}
```

The chart creates the executor namespace, so the second `ExternalSecret`
can only be applied after the chart's first sync. To avoid that, create the
namespace yourself and set `compute.executor.createNamespace: false`
([executor.md](executor.md#who-creates-the-namespaces)).

### After changing a Secret

Appwrite reads credentials when a pod starts. Pods restart on their own only
when the chart's own Secret changes; a change to a Secret you manage does
nothing until you restart them. With GitOps every credential comes from a
Secret you manage, so that applies to all of them. Restart everything in the
release, which briefly interrupts Appwrite while the datastores come
back:

```console
kubectl -n appwrite rollout restart deployment,statefulset -l app.kubernetes.io/instance=appwrite
kubectl -n appwrite-executor rollout restart deployment -l app.kubernetes.io/instance=appwrite   # with Functions and Sites
```

Or let [Reloader](https://github.com/stakater/Reloader) do it. Mark the
chart's workloads for it with `commonAnnotations`, which also lands on other
resources, where Reloader ignores it:

```yaml
commonAnnotations:
  reloader.stakater.com/auto: "true"
```

Run Reloader with `--reload-strategy=annotations`, which Reloader recommends
for GitOps tools so restarts don't show up as drift.

Rotating the built-in PostgreSQL password takes more than a restart:
PostgreSQL only reads it when it creates the database. See
[security.md](security.md#rotating-credentials).

## Server-side apply

Helm 4 installs releases with server-side apply, and so does Argo CD with the
`ServerSideApply=true` sync option used below. Every field then has an
owner. If you change a chart-managed resource with `kubectl edit`, `kubectl
scale` or `kubectl patch`, kubectl takes over those fields and the next
`helm upgrade` stops with a conflict (pass `--force-conflicts` to take them
back). Make changes through values, in Git.

## Migrations

When the Appwrite version changes, its data migration has to run once
([upgrading.md](upgrading.md)). With the Helm CLI and Flux, a post-upgrade
hook does that. The hook only renders during `helm upgrade`, which Argo CD
never runs, so with the default `migrations.mode: hook` Argo CD never
migrates, and nothing tells you. With Argo CD, set `migrations.mode: job`:
the chart then renders a plain Job instead
([upgrading.md](upgrading.md#gitops)).

The Job's name holds the Appwrite version and a short hash of its spec, for
example `appwrite-migrate-2-3-0-a2b2b6df`. A Job's pod template can't be
changed, so a new name is what lets Argo CD sync when the spec changes:

- A chart upgrade that leaves the Job's spec alone keeps the same Job, and
  nothing runs again.
- Changing the Job's spec (a new Appwrite version, but also its resources,
  environment or scheduling) creates a new Job, which runs the migration
  again. Appwrite's migration is idempotent, so that's safe, if slow on a
  large database.
- Deleting the current Job while auto-sync is on makes Argo CD recreate it,
  which also runs the migration again. Delete Jobs of older versions
  whenever you like.

The Job waits until the API answers, but Argo CD applies it together with
the new Deployments, so an API pod of the old version still counts. After
the sync, check that the API rollout finished and the Job succeeded:

```console
kubectl -n appwrite rollout status deployment/appwrite-api
kubectl -n appwrite get jobs -l app.kubernetes.io/component=migrate
```

A failed migration also shows the Application as `Degraded`. Read why with
`kubectl -n appwrite logs job/<name>`, and once the rollout has finished,
run the migration again ([upgrading.md](upgrading.md#gitops)).

Two checks rely on `lookup` and so do nothing under Argo CD: the guard
against downgrading Appwrite (`migrations.allowDowngrade`), and the retry of
a failed hook migration.

## Argo CD

Start from the values in the warning at the top of this page. The chart
is public, so Argo CD can pull it without registering the registry. Note
that `repoURL` has no `oci://` prefix:

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
    targetRevision: 2.3.2
    helm:
      valuesObject:
        appwrite:
          domain: appwrite.example.com
          certificatesEmail: ops@example.com
          secrets:
            generate: false
            existingSecret: appwrite-credentials
        database:
          password:
            secretName: appwrite-credentials
        redis:
          password:
            secretName: appwrite-credentials
        clickhouse:
          password:
            secretName: appwrite-credentials
        storage:
          s3:
            accessKeyId:
              secretName: appwrite-credentials
            secretAccessKey:
              secretName: appwrite-credentials
          volume:
            annotations:
              argocd.argoproj.io/sync-options: Prune=false,Delete=false
        compute:
          secrets:
            existingSecret: appwrite-credentials
          executor:
            existingSecret: appwrite-executor
        migrations:
          mode: job
        # ... the rest of your values
  destination:
    server: https://kubernetes.default.svc
    namespace: appwrite
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

To pull from a private mirror instead, register it as a Helm OCI repository:

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
  url: registry.example.com/appwrite/charts
  enableOCI: "true"
  username: <user>
  password: <token>
```

Things that differ from the Helm CLI:

- **Kept resources.** The `/storage` claim carries
  `helm.sh/resource-policy: keep`. Argo CD treats that as `Delete=false`: it
  keeps the claim when you delete the Application, but still prunes it when
  it leaves the render (for example after renaming the release or turning
  `storage.volume.enabled` off). The `Prune=false` sync option in the example
  covers that. The datastores' claims belong to their StatefulSets, and
  Argo CD leaves them alone. With the values above the chart renders no
  Secret of its own.
- **Tests.** Argo CD ignores Helm test hooks, so the chart's `helm test` pods
  aren't created.
- **No install notes.** Argo CD doesn't show the chart's notes, which carry
  warnings such as queues that no worker consumes. Print them with a client
  dry run, which doesn't touch the cluster:

  ```console
  helm install appwrite oci://ghcr.io/appwrite/charts/appwrite --version 2.3.2 \
    -n appwrite -f values.yaml --dry-run=client | sed -n '/^NOTES:/,$p'
  ```
- **No `ignoreDifferences` needed.** With the values above, two renders are
  identical, and the chart leaves `replicas` out wherever an autoscaler
  manages them.
- **The build and executor namespaces.** With Functions and Sites, the chart
  creates two cluster-scoped Namespaces, `<release namespace>-builds` and
  `<release namespace>-executor`, and puts resources in both. Argo CD applies
  Namespaces before anything else in the same sync. A restricted AppProject
  must allow the `Namespace` kind in `clusterResourceWhitelist` and all three
  namespaces in `destinations`, as below. Or create the namespaces yourself
  and set `compute.builds.createNamespace: false` and
  `compute.executor.createNamespace: false`
  ([executor.md](executor.md#who-creates-the-namespaces)).

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
    - {server: https://kubernetes.default.svc, namespace: appwrite-executor}
  clusterResourceWhitelist:
    - {group: "", kind: Namespace}
```

Namespaced kinds are allowed unless the project lists them. If it sets
`namespaceResourceWhitelist` or `namespaceResourceBlacklist`, allow every
kind the chart renders, including `NetworkPolicy`, `Role` and `RoleBinding`.

## Flux

Flux runs Helm, so generated credentials and the migration hook behave as
with the Helm CLI. Create the `appwrite` namespace first; the `HelmRelease`
lives in it.

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
    timeout: 15m   # the API's first start creates the database schema
  upgrade:
    timeout: 2h    # covers the data migration (migrations.activeDeadlineSeconds)
  values:
    appwrite:
      domain: appwrite.example.com
      certificatesEmail: ops@example.com
```

If your Flux disallows cross-namespace references, put the `OCIRepository`
in the `appwrite` namespace too.

Leave `upgrade.remediation` at its defaults. With `retries` set, Flux rolls
back a failed upgrade, which after a failed migration puts the old Appwrite
version back on partly migrated data ([upgrading.md](upgrading.md#rolling-back)).

To have Flux check the chart's signature, add `verify` to the
`OCIRepository`. The chart is signed with cosign 3, which needs Flux 2.8 or
later ([security.md](security.md#verifying-chart-signatures)):

```yaml
spec:
  verify:
    provider: cosign
    matchOIDCIdentity:
      - issuer: ^https://token\.actions\.githubusercontent\.com$
        subject: ^https://github\.com/appwrite/helm-chart/\.github/workflows/release\.yaml@refs/heads/main$
```
