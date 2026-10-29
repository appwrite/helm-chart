# Troubleshooting

Find the symptom below; each entry gives the cause and the fix. The commands
use the release `appwrite` in the namespace `appwrite`.

Start with what Kubernetes says:

```console
kubectl -n appwrite get pods
kubectl -n appwrite describe pod <pod>
kubectl -n appwrite get events --sort-by=.lastTimestamp
```

Then read the logs of the component involved:

| Component | Logs |
| --- | --- |
| API | `kubectl -n appwrite logs deploy/appwrite-api` |
| Realtime | `kubectl -n appwrite logs deploy/appwrite-realtime` |
| Workers, `workers.mode: combined` (default) | `kubectl -n appwrite logs deploy/appwrite-worker` |
| Workers, `separate` | `deploy/appwrite-worker-<queue>`, e.g. `appwrite-worker-mails`, `appwrite-worker-stats-usage` |
| Workers, `grouped` | `deploy/appwrite-worker-<group>`, and `appwrite-worker-maintenance` when no group lists `maintenance` |
| Scheduler | `deploy/appwrite-scheduler`; with `tasks.scheduler.mode: separate`, `appwrite-scheduler-functions`, `-executions`, `-messages`, `-maintenance` |
| Maintenance, interval tasks | `deploy/appwrite-maintenance`, `deploy/appwrite-interval` |
| Built-in datastores | `appwrite-postgresql-0`, `appwrite-redis-0`, `appwrite-clickhouse-0` |
| Migration Job | `job/appwrite-migrate` (hook), or the `appwrite-migrate-<version>-<hash>` Job with `migrations.mode: job` |
| ExifTool | `deploy/appwrite-exiftool`; the API logs "Image metadata was not removed" when stripping fails |
| Functions and Sites | `deploy/appwrite-orchestrator`, and in `appwrite-executor`, `deploy/appwrite-executor` |

Add `--previous` to read the log of a container that crashed and restarted.

## Installation

### The render fails with "Invalid values"

```text
Invalid values:
  - appwrite.domain is required: set it to the hostname users reach Appwrite on, e.g. --set appwrite.domain=appwrite.example.com.
```

The chart checks its values before rendering anything. Each line names the
value to change and why.

### The render fails with "No value for ..."

```text
No value for _APP_GEO_SECRET: provide it explicitly or through an existing Secret (appwrite.secrets.generate is false).
```

`appwrite.secrets.generate` is `false` and the named credential has no
source. Add the key to your Secret and name the Secret in the matching
`existingSecret`, or in the credential's `secretName`
([gitops.md](gitops.md#what-goes-in-the-secrets)).

### An upgrade refuses to generate a new key or password

```text
Refusing to generate a new _APP_OPENSSL_KEY_V1 during an upgrade: Secret appwrite/appwrite was not found.
Refusing to generate a new db-password during an upgrade: Secret appwrite/appwrite was not found, and the existing data volume keeps the old password.
```

The chart's Secret is gone, so `helm upgrade` would generate new values that
don't match the existing data. Restore the Secret from your backup
([backup-restore.md](backup-restore.md#credentials)), or set
`appwrite.secrets.existingSecret` or the explicit values
(`appwrite.secrets.opensslKey`, `database.password`). With
`helm upgrade --dry-run`, use `--dry-run=server` so Helm can read the
existing Secret.

### The render fails with "opensslKey differs from the key stored in the cluster"

`appwrite.secrets.opensslKey` doesn't match the `_APP_OPENSSL_KEY_V1` the
install already uses. Appwrite can't re-encrypt data with a new key, so put
the stored key back in your values. Set `appwrite.secrets.allowKeyRotation`
only if you mean to give up the encrypted data.

### Pods restart, or Appwrite can't decrypt or log in, after every Argo CD sync

Argo CD renders the chart without cluster access, so with the default
`appwrite.secrets.generate: true` every render generates a new encryption key
and new passwords. Turn off auto-sync, then switch to Secrets you manage,
filled with the values the data was created with (from your backup of the
chart's Secret), and `generate: false` ([gitops.md](gitops.md#credentials)).

### Pods stay in `Init`

Init containers wait for dependencies:

| Init container | In | Waits for |
| --- | --- | --- |
| `wait-for-datastores` | API | PostgreSQL, Redis and ClickHouse to accept connections |
| `wait-for-api` | realtime, workers, tasks, migration Job | the API to answer |

So check the API first:

```console
kubectl -n appwrite logs deploy/appwrite-api -c wait-for-datastores
kubectl -n appwrite logs deploy/appwrite-api
```

`wait-for-datastores` prints the host it's waiting for; see
[External services](#external-services) if it never finishes.

### The API takes minutes to become ready on first install

It creates the console database, buckets and ClickHouse tables on its first
start. The startup probe allows six minutes; on slow storage, raise
`api.startupProbe.failureThreshold` (in steps of five seconds).

### The API can't log in to the built-in PostgreSQL

```text
password authentication failed for user "appwrite"
```

PostgreSQL only reads its password when it creates the database, so the
volume still expects the old one. This happens when the chart's Secret was
deleted and regenerated, or when the password in your own Secret changed. Put
the original password back from your backup
([backup-restore.md](backup-restore.md#credentials)), or change it in
PostgreSQL first ([security.md](security.md#rotating-credentials)).

### Pods stay `Pending`

`kubectl describe pod` shows why:

| Message | Cause | Fix |
| --- | --- | --- |
| `didn't match pod affinity rules` | With a ReadWriteOnce `/storage` volume, every pod that mounts it must run on the node the volume is attached to, and that node is full. | Give that node more room, or use ReadWriteMany or S3 so the pods can spread ([storage.md](storage.md#readwriteonce-vs-readwritemany)). |
| `pod has unbound immediate PersistentVolumeClaims` | A claim isn't bound. `kubectl -n appwrite get pvc` and `describe pvc` say why, often `no storage class is set`. | Set `global.storageClass` (or `storage.volume.storageClass` and the datastores' own `builtin.persistence.storageClass`) to a class that exists, or mark one as the cluster default. |
| `persistentvolumeclaim "..." not found` | `storage.volume.existingClaim` names a claim that doesn't exist in the namespace. | Create the claim, or fix the name. |

### Pods are rejected by Pod Security admission

A Deployment has no pods, and `kubectl -n appwrite get events` shows:

```text
Error creating: pods "appwrite-api-..." is forbidden: violates PodSecurity "restricted:latest": ...
```

Every pod in the Appwrite namespace passes `restricted` with the default
security contexts. If you overrode one (`podSecurityContext`,
`containerSecurityContext`, per component or at the top level), check it
against the
[restricted profile](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted).
Build Jobs and the executor run in namespaces of their own, under `baseline`
and `privileged` ([security.md](security.md#functions-and-sites)).

## External services

[external-databases.md](external-databases.md#checking-a-connection) shows how
to test a connection from inside the namespace.

### `kubectl run` debug pods are rejected

```text
Error from server (Forbidden): pods "db-check" is forbidden: violates PodSecurity "restricted:latest": ...
```

In a namespace that enforces `restricted`, a pod started with `kubectl run`
needs a security context too. Pass one with `--overrides`; the container's
`name` must match the pod's name:

```console
kubectl -n appwrite run db-check --rm -it --restart=Never --image=postgres:18-alpine \
  --override-type=strategic --overrides='{"spec": {
    "securityContext": {"runAsNonRoot": true, "runAsUser": 65534, "seccompProfile": {"type": "RuntimeDefault"}},
    "containers": [{"name": "db-check", "securityContext": {"allowPrivilegeEscalation": false, "capabilities": {"drop": ["ALL"]}}}]}}' \
  -- psql "host=appwrite-db.example.internal user=appwrite dbname=appwrite" -c 'select version()'
```

### `wait-for-datastores` never finishes

The host or port isn't reachable from the cluster. Check the name, security
groups, firewall rules and IP allow lists (ClickHouse Cloud has one), and
`networkPolicy.egress` if you restricted it.

### PostgreSQL: an extension is missing

```text
extension "postgis" is not available
permission denied to create extension "vector"
```

The server lacks PostGIS, pgvector or pg_trgm, or the Appwrite user may not
create them. Create them as an administrator
([requirements](external-databases.md#requirements)); on Azure, allow them in
`azure.extensions` first.

### PostgreSQL: restoring a built-in dump fails on extensions

```text
type "appwrite.geometry" does not exist
must be owner of extension postgis
```

A dump of the built-in PostgreSQL has its extensions in the `appwrite`
schema, and restoring as a user that isn't a superuser can't recreate them.
Follow [moving from built-in to external](external-databases.md#moving-from-built-in-to-external),
which prepares the schema first.

### MariaDB or MySQL: "Connections using insecure transport are prohibited"

The server requires TLS, which Appwrite's MySQL client doesn't use. Turn off
`require_secure_transport` and keep the traffic on a private network.

### Redis: connection resets or timeouts against a managed Redis

The service expects TLS (ElastiCache with in-transit encryption, ElastiCache
Serverless, Azure's TLS port, Upstash). Appwrite 2.6.2 connects in plain text
only; use a plain-text endpoint on a private network
([Redis](external-databases.md#redis)).

### ClickHouse: authentication fails although the password is right

The password contains a character that isn't URL-safe (`+`, `/`, `@`, `%`,
...), and Appwrite puts it into a connection URL unencoded. Use one made of
letters and digits, for example from `openssl rand -hex 32`. This applies to
the built-in ClickHouse with your own Secret too.

### S3: uploads fail with `SignatureDoesNotMatch`, `AccessDenied` or `NoSuchBucket`

With your own store, check `storage.s3.external.region` (R2 and GCS use
`auto`), that the bucket exists, and that the key may read, write, list and
delete in it. With an `external.endpoint`, Appwrite uses path-style URLs,
which the store must accept ([storage.md](storage.md#your-own-s3-store)). With
the built-in object storage, check that the `seaweedfs` pod is ready: it
creates the bucket when it starts.

### Emails don't arrive

The worker that consumes the `mails` queue logs the SMTP error, and most
providers reject senders on domains you haven't verified
([integrations.md](integrations.md#email-smtp)).

## Requests

### Every request redirects to HTTPS, or the browser reports too many redirects

`appwrite.forceHttps` is on and the request didn't arrive with
`X-Forwarded-Proto: https`. Appwrite answers `GET` requests with a 301 to
`https://` and other methods with 426, "Method unsupported over HTTP".

- Nothing in front of Appwrite terminates TLS: turn `forceHttps` off, or
  enable TLS on the ingress ([networking.md](networking.md#tls-and-forcehttps)).
- TLS ends at a load balancer in front of the ingress controller: the
  controller must pass the load balancer's `X-Forwarded-Proto` on instead of
  replacing it with `http` (for ingress-nginx, `use-forwarded-headers: "true"`).

### "Router protection does not allow accessing Appwrite over this domain" (401)

`appwrite.routerProtection` is on and the hostname isn't `appwrite.domain`,
`appwrite.consoleDomain` or a custom domain a project has added.

### The console loads, but API calls fail (404)

Requests to `/v1` must reach the API, not the console. This is what happens
with a `kubectl port-forward` to the console Service alone: the console
sends API calls to its own address. Route through an ingress controller
([getting-started.md](getting-started.md)), and check your routes with
`hack/routes.sh` ([networking.md](networking.md#testing-routes)).

### Requests fail with 500 for a moment after PostgreSQL restarts

Appwrite keeps database connections open. After a restart, the first request
on each stale connection fails (`terminating connection due to administrator
command` in the API log) and Appwrite reconnects. It settles within seconds.

### Realtime disconnects every minute

The ingress controller or a load balancer closes idle WebSockets. Raise its
idle timeout to a few minutes
([networking.md](networking.md#upload-limits-and-timeouts)).

## Background work

### Database attributes stay `processing`; emails or webhooks don't go out

No worker consumes the queue. Check that the worker pods run (see the table
at the top for their names), and look for this warning in the install notes
(`helm -n appwrite get notes appwrite`):

```text
WARNING: no worker consumes these queues, so their jobs will pile up in Redis:
```

With `workers.mode: separate` or `grouped`, enable a Deployment for each
queue it names ([architecture.md](architecture.md#worker-topologies)).
[production.md](production.md#queues) shows how to see which queues have
jobs waiting, and [the health API](production.md#health-api) counts failed
jobs per queue.

### Scheduled functions run twice

Two scheduler pods are running. The chart runs one and replaces it with
`Recreate`, so something else scaled the Deployment. Scale it back to 1.

### Custom domains never verify

`appwrite.domainTargets` must match where the domain points, and the domain's
DNS must have propagated. The interval task checks unverified domains every
two minutes ([networking.md](networking.md#custom-domains)).

## Upgrades

### `helm upgrade` fails or times out in the migration

The post-upgrade hook Job ran `migrate` and failed, or `--timeout` ran out
first while it kept running. Read its log with
`kubectl -n appwrite logs job/appwrite-migrate`, then follow
[upgrading.md](upgrading.md#if-the-migration-fails). Don't roll back:
the new version's migration may already have changed the data.

### The render fails with "this would downgrade it"

The chart's Appwrite version is older than the one running. Appwrite can't
migrate data backwards; restore a backup taken before the upgrade instead
([upgrading.md](upgrading.md#rolling-back)).

## Functions and Sites

Deployments that stay `waiting`, builds that fail, executor pods that don't
start, executions that time out: see
[executor.md](executor.md#troubleshooting).

### Site deployments log "Screenshot capturing failed"

The site deploys and serves, but its deployment log ends with "Screenshot
capturing failed" and the console shows no preview. The worker that
consumes the screenshots queue logs the cause; this finds it with any
`workers.mode`:

```console
kubectl -n appwrite logs -l appwrite/role=worker --prefix --tail=2000 | grep -i screenshots | tail -1
```

- `Could not resolve host: appwrite-browser`: the browser is off
  (`browser.enabled: false`). Turn it on and redeploy the site; screenshots
  are only taken during a deployment
  ([optional-components.md](optional-components.md#browser)).
- `Hostname ... does not resolve` (in the API's log for
  `/v1/avatars/screenshots`): with `networkPolicy.egress.enabled`, Appwrite
  can't reach the resolver it checks URLs with (`_APP_DNS_EXTERNAL`, by
  default 8.8.8.8). Allow it
  ([networking.md](networking.md#requests-to-private-addresses)).
- A timeout, or a refused connection to the API: with `networkPolicy.enabled`,
  the browser may only reach DNS, the API and public addresses
  ([security.md](security.md#network-policies)); check that its egress
  policy matches your DNS ([networking.md](networking.md#networkpolicies-and-dns)).

### Deployments fail with an internal error

Every deployment fails with "An internal error occurred while building", and
creating a function or site from a template fails with a 500. Retrying then
fails with a 409, "Domain is already used", because the first attempt already
created the function and its domain. The API's log names the cause:

```console
kubectl -n appwrite logs deploy/appwrite-api | grep -i 'resolve host'
```

`Could not resolve host: orchestrator` (or `exc1`) means Functions and Sites
are off (`compute.enabled: false`): Appwrite falls back to the Docker
install's hostnames, which don't exist in the cluster, and the console offers
Functions and Sites anyway. Turn compute on ([executor.md](executor.md)), or
hide Functions and Sites in each project's settings (Settings → Services).
Delete the functions the failed attempts left behind.

## FAQ

### Is it highly available?

Appwrite's own pods can be: run several API, console and realtime replicas
or autoscale the API, and give `/storage` a ReadWriteMany volume so they
spread across nodes. A few pieces always run as one pod, because Appwrite
has no leader election for them: the scheduler, the maintenance and interval
tasks, and the worker that consumes the `databases` queue
([architecture.md](architecture.md#components)).

The built-in PostgreSQL, Redis and ClickHouse are single replicas without
failover. For high availability, use managed services or operators
([external-databases.md](external-databases.md)) and work through the
[production checklist](production.md).

### Why is the executor privileged, and what are the alternatives?

The open-runtimes executor runs each function and site in a container of its
own, started by a Docker daemon inside the executor pod. That daemon needs a
privileged container, which is root on its node. Functions and Sites are on
by default, so a plain install runs one, in a namespace of its own. For
production, give it nodes of its own
([executor.md](executor.md#executor-isolation)); where privileged pods aren't
allowed, set `compute.enabled: false`. Builds don't need it: they run as
ordinary Jobs.

The alternative is [Sysbox](https://github.com/nestybox/sysbox), which runs
the daemon without `privileged`: install it on the executor's nodes and set
`compute.executor.privileged: false` with
`compute.executor.runtimeClassName: sysbox-runc`
([executor.md](executor.md#without-a-privileged-container)). CI doesn't test
it.

### Does it expose Prometheus metrics?

Appwrite 2.6.2 has no metrics endpoint. Watch its health API, its queues and
its logs, plus the metrics of Kubernetes and the datastores. The built-in
datastores can run exporters (`database.builtin.metrics`,
`redis.builtin.metrics`, `clickhouse.builtin.metrics`) with ServiceMonitors
(`metrics.serviceMonitor`). See
[production.md](production.md#monitoring).

### Helm 3 or Helm 4?

Either: Helm 4, or Helm 3.18 or later. CI lints and renders the chart with
both, and installs it with Helm 4. To move a release from Helm 3 to Helm 4,
see [upgrading.md](upgrading.md#helm-3-to-helm-4).

### Should I use the Docker install or this chart?

Appwrite's Docker Compose install runs everything on one server and is the
simpler choice there. The chart runs the same images on Kubernetes: use it
when you already run Kubernetes and want managed datastores, replicas across
nodes, rolling upgrades or GitOps. Functions and Sites run on a privileged
executor here too, and on object storage, built-in or your own
([executor.md](executor.md)). To move an
existing Docker install, see
[migrating-from-docker.md](migrating-from-docker.md).

### Can I use an existing PostgreSQL or Redis?

Yes. Set the service's `mode` to `external`, and give its address and
password:

```yaml
database:
  mode: external
  external:
    host: appwrite-db.example.internal
  password:
    secretName: appwrite-db        # key db-password
redis:
  mode: external
  external:
    host: appwrite-redis.example.internal
```

PostgreSQL needs the `postgis`, `vector` and `pg_trgm` extensions and a
direct connection, without a transaction-mode pooler. Redis needs a single
endpoint without TLS. See [external-databases.md](external-databases.md) and
[`examples/external-services.yaml`](../examples/external-services.yaml).

### How do I add my own Kubernetes objects?

Put them in `extraObjects`, a list or a map of manifests. Each one is
rendered with `tpl`, so it can use `{{ .Release.Name }}` and other template
values, and is deployed with the release. With a map, several values files
can add objects without replacing each other's. For example, a
PodDisruptionBudget for the `usage` worker group of
[`examples/production.yaml`](../examples/production.yaml):

```yaml
extraObjects:
  - apiVersion: policy/v1
    kind: PodDisruptionBudget
    metadata:
      name: '{{ .Release.Name }}-worker-usage'
    spec:
      maxUnavailable: 1
      selector:
        matchLabels:
          app.kubernetes.io/instance: '{{ .Release.Name }}'
          app.kubernetes.io/component: worker-usage
```

## Getting help

Collect the output of:

```console
helm -n appwrite list
helm -n appwrite get values appwrite
kubectl -n appwrite get pods,events
kubectl -n appwrite logs deploy/appwrite-api --tail=200
```

With Argo CD, include the Application's values instead of
`helm get values`. Remove passwords and keys from the output, then open an
issue at <https://github.com/appwrite/helm-chart/issues>. Problems in
Appwrite itself belong at <https://github.com/appwrite/appwrite/issues>.
