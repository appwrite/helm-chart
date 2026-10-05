# Architecture

This page explains what the chart deploys, how the pieces talk to each other,
and which Appwrite settings the chart wires up for you.

## Components

```mermaid
flowchart LR
  user([Browser / SDK]) --> edge{{Ingress or Gateway}}

  edge -- "/v1/realtime" --> realtime[realtime]
  edge -- "/v1, /.well-known,\n*.functions, *.sites,\ncustom domains" --> api[api]
  edge -- "everything else" --> console[console]

  api --> geo[geo]
  api --> pg[(PostgreSQL)]
  api --> redis[(Redis)]
  api --> ch[(ClickHouse)]
  realtime --> pg
  realtime --> redis

  redis -- queues --> worker[workers]
  scheduler[scheduler] -- enqueue --> redis
  maintenance[maintenance] -- enqueue --> redis
  interval[interval] --> pg

  worker --> pg
  worker --> ch
  api --- storage[(/storage volume\nor S3)]
  worker --- storage

  worker -. "builds and executions\n(optional, external)" .-> executor[[open-runtimes executor\non a Docker host]]
  api -. "function and site traffic" .-> executor
```

| Component | Image | Command | Scales | Notes |
| --- | --- | --- | --- | --- |
| `api` | `appwrite/appwrite` | `php app/http.php` | Horizontally (HPA) | REST and GraphQL API. Also proxies function, site and custom-domain traffic, and serves ACME challenges. |
| `console` | `appwrite/new` | image default | Horizontally (HPA) | The web console, a separate Bun app. |
| `realtime` | `appwrite/appwrite` | `php app/realtime.php` | Horizontally (HPA) | WebSocket server for `/v1/realtime`. One Swoole worker per pod by default. |
| `worker` | `appwrite/appwrite` | `php app/worker.php all` | See [worker topologies](#worker-topologies) | Consumes every queue: database changes, deletes, mails, webhooks, certificates, usage, builds and more. |
| `scheduler` | `appwrite/appwrite` | `php app/cli.php schedule` | **One replica** | Enqueues scheduled function executions and messages. |
| `maintenance` | `appwrite/appwrite` | `php app/cli.php maintenance` | **One replica** | Periodic cleanup and certificate renewals. |
| `interval` | `appwrite/appwrite` | `php app/cli.php interval` | **One replica** | Custom domain verification and stale execution cleanup. |
| `geo` | `appwrite/geo` | image default | Horizontally | IP geolocation for sessions and logs. |
| `postgresql` | `appwrite/postgres` | `postgres` | One replica | Built-in database. Optional. |
| `redis` | `redis` | `redis-server` | One replica | Cache, queues, pub/sub and locks. Optional. |
| `clickhouse` | `clickhouse/clickhouse-server` | image default | One replica | Usage statistics and execution logs. Optional. |

The scheduler, maintenance and interval tasks have no leader election in
Appwrite, so a second copy would do the same work twice. The chart always runs
exactly one of each and recreates (rather than rolls) them on updates.

## Worker topologies

Appwrite's work happens on 15 Redis queues. `workers.mode` decides how they're
spread over Deployments:

| Mode | Deployments | When to use |
| --- | --- | --- |
| `combined` (default) | `worker`, consuming every queue | Small installs. Uses the least memory. |
| `separate` | `worker-<queue>`, one per queue in `workers.queues` | Scale or size each queue independently. Matches Appwrite's `docker-compose.separate.yml`. |
| `grouped` | `worker-<group>`, one per entry in `workers.groups` | Isolate noisy queues (usage, builds) without running 15 pods. |

```yaml
workers:
  mode: grouped
  groups:
    core:
      queues: [databases, deletes, mails, messaging, notifications, certificates, migrations, webhooks]
    usage:
      queues: [stats-usage, stats-resources]
      replicaCount: 2
    compute:
      queues: [builds, jobs, functions, executions, screenshots]
```

The `databases` queue applies schema changes in order and must have exactly
one consumer, so whichever Deployment consumes it is capped at one replica
and never autoscaled. In `combined` mode that is the only worker, which is why
`workers.combined.replicaCount` can't exceed 1; switch to `separate` or
`grouped` to scale the rest.

`_APP_WORKER_MAX_COROUTINES` sizes each worker's connection pool. The chart
sets it to the queue's own concurrency in `separate` mode (as Appwrite's
compose file does) and to the sum of its queues' concurrency in `grouped` mode.

Only workers whose queues touch files mount the `/storage` volume: deletes,
builds, jobs, screenshots, certificates, messaging and migrations. That keeps
the ReadWriteOnce co-location to the pods that need it.

`tasks.scheduler.mode: separate` similarly splits the scheduler into
`scheduler-functions`, `scheduler-executions`, `scheduler-messages` and
`stats-resources`. Each still runs as a single replica.

Queues no Deployment consumes (a disabled queue in `separate` mode, or a
queue missing from every group) are listed as a warning after install or
upgrade. Their jobs pile up in Redis until something consumes them.

## Startup order

Kubernetes has no `depends_on`, so the chart uses init containers:

1. The API waits until PostgreSQL, Redis and ClickHouse accept TCP connections.
2. On start, every API pod creates the console database, buckets and ClickHouse
   tables if they don't exist yet. This is idempotent and can take a few
   minutes on the first install, which is why the API's startup probe is generous.
3. Realtime, workers and tasks wait until the API answers on
   `/v1/health/version`. Appwrite's CLI tasks and workers exit when they start
   before the schema exists.

## Configuration flow

Every Appwrite pod gets the same configuration:

- **`<fullname>-env` ConfigMap**, loaded with `envFrom`. It starts from the
  defaults Appwrite's Docker installer writes to `.env`
  ([`files/env-defaults.yaml`](../charts/appwrite/files/env-defaults.yaml)),
  then applies values the chart computes, then `appwrite.config`.
- **Secrets**, referenced one variable at a time with `secretKeyRef`, so the
  chart works the same whether a credential comes from the chart's own Secret
  or from one you manage.
- **Per-pod variables** that depend on the component: `PORT`, `_APP_CPU_NUM`,
  `_APP_WORKERS_NUM`, `_APP_WORKER_MAX_COROUTINES` and the ClickHouse
  connection strings. Kubernetes gives these precedence over the ConfigMap,
  so `appwrite.config` can't override them; use the component's values
  (`cpuNum`, `processes`, `maxCoroutines`) instead.

Pods carry checksums of the ConfigMap and the chart Secret, so changing values
rolls them. Changes to Secrets you manage yourself don't; use a tool such as
[Reloader](https://github.com/stakater/Reloader) for that.

### Values the chart computes

| Variable | Value |
| --- | --- |
| `_APP_DOMAIN`, `_APP_CONSOLE_DOMAIN` | `appwrite.domain`, `appwrite.consoleDomain` |
| `_APP_DOMAIN_FUNCTIONS`, `_APP_DOMAIN_SITES` | `functions.<domain>`, `sites.<domain>` unless set |
| `_APP_DOMAIN_TARGET_CNAME` | `appwrite.domain` unless set |
| `_APP_DB_*` | the built-in PostgreSQL Service |
| `_APP_REDIS_*` | the built-in Redis Service |
| `_APP_CONNECTIONS_DB_USAGE`, `_APP_CONNECTIONS_DB_EXECUTIONS` | the built-in ClickHouse Service |
| `_APP_GEO_ENDPOINT` | the geo Service, or empty when geo is disabled |
| `_APP_MIGRATION_HOST` | the API Service name |
| `_APP_WORKER_SCREENSHOTS_ROUTER`, `_APP_JOBS_ENDPOINT` | the API Service URL |
| `_APP_CPU_NUM` | each component's CPU limit (or request), rounded up |

### Why `_APP_CPU_NUM` matters

Appwrite sizes its Swoole worker count and its database connection pools from
the CPU count. Without `_APP_CPU_NUM` it reads the node's CPUs, ignoring the
container limit, so a small pod on a 64-core node starts hundreds of workers
and opens far more database connections than intended. The chart sets it from
each component's resources; override it with `<component>.cpuNum`.

Connection pools are split across pods with `_APP_CONNECTIONS_MAX`
(`appwrite.database.connectionsMax`, the total budget) and `_APP_POOL_CLIENTS`
(`appwrite.database.poolClients`, how many pods share it). Keep `poolClients`
at least as large as the number of Appwrite pods. The built-in PostgreSQL sets
`max_connections` to `connectionsMax + 20`.

### Health checks without a Host lookup

Appwrite routes every request by its `Host` header and looks unknown hosts up
in the database (custom domains), redirecting to HTTPS when `forceHttps` is on.
The chart sets `_APP_MIGRATION_HOST` to the API Service name, which Appwrite
treats as an internal hostname, and its probes send `Host: <fullname>-api`.
Probes then skip both the lookup and the redirect.

## Storage

Appwrite keeps files under `/storage`:

| Path | Contents | Where |
| --- | --- | --- |
| `/storage/uploads` | Bucket files | shared volume, or S3 |
| `/storage/functions`, `/storage/sites`, `/storage/builds` | Deployment code and build output | shared volume, or S3 |
| `/storage/imports` | Migration imports | shared volume, or S3 |
| `/storage/certificates`, `/storage/config` | Let's Encrypt certificates and ACME challenges | shared volume |
| `/storage/cache` | Image previews and other cached responses | per-pod `emptyDir` |

The chart creates one PersistentVolumeClaim and mounts each path as a
`subPath`. With a ReadWriteOnce volume (the default), every pod that mounts
it is scheduled on the same node through pod affinity, so the volume can be
attached. To spread the API and workers across nodes, use a ReadWriteMany
storage class or S3.

The cache is per pod: Appwrite only serves a cached file when the database
says it exists, so a pod that hasn't cached it yet just regenerates it.

## Security

All pods run as non-root with a read-only root filesystem, no capabilities and
the `RuntimeDefault` seccomp profile, so they're admitted under the Pod
Security Standard `restricted` profile. Writable paths are `emptyDir`s.

- The Appwrite image runs as `www-data` (UID 82). The API and realtime listen
  on 8080 instead of 80.
- The geo image listens on port 80, so its pod sets the namespaced sysctl
  `net.ipv4.ip_unprivileged_port_start=0`, which the `restricted` profile allows.
- ServiceAccount tokens aren't mounted; nothing in Appwrite uses the
  Kubernetes API, and the chart creates no RBAC.
