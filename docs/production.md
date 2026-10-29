# Production checklist

Go through this list before real users depend on an install. Each item links
to the guide that explains it.

## Data

- [ ] **Managed or operator-run datastores.** Set `database.mode`,
      `redis.mode` and `clickhouse.mode` to `external` and use replicated
      services with backups ([external-databases.md](external-databases.md)).
- [ ] **Credentials backed up** outside the cluster: the whole chart Secret,
      not just the encryption key, because the built-in PostgreSQL's password
      is tied to its volume ([backup-restore.md](backup-restore.md#credentials)).
      Or provide them from your secret manager with
      `appwrite.secrets.existingSecret` and each credential's `secretName`
      ([security.md](security.md#bringing-your-own-secrets)).
- [ ] **Backups** of the database and files, with a tested restore
      ([backup-restore.md](backup-restore.md)).
- [ ] **A ReadWriteMany volume** for `/storage`, so API and worker pods can
      spread across nodes. With S3 the volume can be small, but it's still
      mounted, and a ReadWriteOnce claim keeps those pods on one node
      ([storage.md](storage.md#the-volume-with-s3)).

## Traffic

- [ ] **TLS** at the ingress or Gateway, with `appwrite.forceHttps: true`
      (the default) ([networking.md](networking.md#tls-and-forcehttps)).
- [ ] **Wildcard certificates** for `*.functions.<domain>` and
      `*.sites.<domain>` if you use Functions or Sites. They need a DNS-01
      issuer ([networking.md](networking.md#cert-manager)).
- [ ] **`appwrite.domainTargets`** set to your load balancer, so custom
      domains verify ([networking.md](networking.md#custom-domains)).
- [ ] **Body size and timeouts** on the controller suit uploads (30 MB by
      default), realtime WebSockets and synchronous executions
      ([networking.md](networking.md#upload-limits-and-timeouts)).
- [ ] **Client IPs** reach Appwrite in `X-Forwarded-For` and can't be spoofed
      ([networking.md](networking.md#tls-and-forcehttps)).

## Capacity

- [ ] **Resources** on every component, sized from real usage. `_APP_CPU_NUM`
      follows the CPU limit, or the request when there's no limit; set
      `cpuNum` where that isn't what the pod really gets
      ([architecture.md](architecture.md#why-_app_cpu_num-matters)).
- [ ] **Replicas and autoscaling** for the API, console and realtime
      (`replicaCount`, `autoscaling.enabled`).
- [ ] **PHP memory limit** raised for a realtime that holds thousands of
      connections: `appwrite.config._APP_MEMORY_LIMIT` (512M per PHP
      process, `-1` for none) applies to every Appwrite pod, so raise
      `realtime.resources.limits.memory` with it.
- [ ] **Function and site specifications capped** with
      `appwrite.config._APP_COMPUTE_CPUS` and `_APP_COMPUTE_MEMORY`, if you
      run Functions and Sites. Without a cap, Appwrite offers up to 8 CPUs and
      8 GB per function, and builds are sized the same way
      ([executor.md](executor.md#build-resources)).
- [ ] **Connection budget:** every Appwrite pod at peak, counting HPA
      maximums, fits in the database's `max_connections`
      ([external-databases.md](external-databases.md#connections)). Workers
      size their pools from `maxCoroutines`, not from `connectionsMax`
      ([architecture.md](architecture.md#database-connections)).
- [ ] **Worker topology:** `separate` or `grouped` when one queue (usage,
      builds) shouldn't slow down the others
      ([architecture.md](architecture.md#worker-topologies)).
- [ ] **Redis memory** big enough that it never fills up. The built-in Redis
      evicts least-recently-used keys when it reaches `redis.builtin.maxmemory`
      (512 MB; `allkeys-lru`, as in Appwrite's Docker install). A queue is a
      key, so an evicted queue loses its jobs.

## Availability

- [ ] **Node drains planned for.** Only the API, console and realtime get
      PodDisruptionBudgets, and only when more than one replica can run.
      Workers, tasks, geo, the executor and the built-in datastores have
      none, so nothing limits how many of them a drain evicts at once. Drain
      one node at a time
      ([architecture.md](architecture.md#probes-and-disruption-budgets)).
- [ ] **Functions and Sites** (on by default): the executor on nodes of its
      own ([executor.md](executor.md#executor-isolation)), with replicas and
      resources for the executions you expect
      ([executor.md](executor.md#sizing)); or `compute.enabled: false` if you
      don't use them, which removes the privileged executor pod.
- [ ] **Object storage with redundancy:** your own S3 store
      ([storage.md](storage.md#your-own-s3-store)), or backups of the
      built-in store's volume, which is a single replica
      ([storage.md](storage.md#built-in-object-storage)).

## Operations

- [ ] **`appwrite.logFormat: json`** (the default) shipped to your log
      pipeline.
- [ ] **Error tracking:** set `_APP_LOGGING_CONFIG` to a Sentry DSN through
      `appwrite.secretConfig` ([integrations.md](integrations.md#error-tracking)).
- [ ] **Monitoring and alerts** for the signals [below](#monitoring).
- [ ] **SMTP** configured (`smtp`), so verification and password
      emails go out ([integrations.md](integrations.md#email-smtp)).
- [ ] **Console sign-up** restricted: `appwrite.console.whitelistRoot` (the
      default) lets only the first account sign up;
      `appwrite.console.whitelistEmails` and `whitelistIPs` narrow it further.
- [ ] **NetworkPolicies** (`networkPolicy.enabled`), with the entry points
      limited to your ingress controller (`networkPolicy.ingress.from`)
      ([security.md](security.md#network-policies)). With Functions and Sites,
      restrict who can read pods and Jobs in the build namespace
      ([security.md](security.md#functions-and-sites)).
- [ ] **Upgrades** rehearsed on a copy of production
      ([upgrading.md](upgrading.md)).

## Monitoring

Appwrite 2.6.2 exposes no Prometheus metrics. You have its logs, its health
API, and the metrics of Kubernetes and your datastores.

| Watch | How | Alert when |
| --- | --- | --- |
| Pod restarts | `kubectl -n appwrite get pods`, or `kube_pod_container_status_restarts_total` from kube-state-metrics | Restarts keep rising. Workers and tasks have no probes: Kubernetes restarts them only when they exit, and a hung one shows up only in its queue. |
| Queue backlog | Length of each queue in Redis ([below](#queues)) | A queue keeps growing: its worker is behind, hung or missing. |
| Failed jobs | `/v1/health/queue/failed/<queue>` | The count rises. |
| Datastores, as the API sees them | `/v1/health/db`, `/v1/health/cache`, `/v1/health/pubsub`, `/v1/health/usage`, `/v1/health/storage` | A check fails. The API's probes don't test the datastores. |
| Redis memory | `redis-cli info memory` and `info stats` | `used_memory` nears `maxmemory`, or `evicted_keys` rises. |
| Volume usage | `kubelet_volume_stats_used_bytes` and `kubelet_volume_stats_capacity_bytes` | `/storage` or a datastore volume passes 80%. |
| Database connections | `pg_stat_activity` against `max_connections` | Connections near the limit ([sizing](architecture.md#database-connections)). |
| Certificate expiry | `/v1/health/certificate?domain=<domain>`, or cert-manager's metrics | `validTo` is less than two weeks away. |

### Health API

Every endpoint except `/v1/health/version` needs an API key. Appwrite grants
the `health.read` scope to every project API key, so create one in any
project in the console:

```console
curl -s https://appwrite.example.com/v1/health/db \
  -H "X-Appwrite-Project: <project-id>" \
  -H "X-Appwrite-Key: <api-key>"
```

A passing check answers `200`; a failing one returns an error status and a
message.

| Endpoint | Checks |
| --- | --- |
| `/v1/health` | The API answers. |
| `/v1/health/db` | The console and project databases answer a ping. |
| `/v1/health/cache`, `/v1/health/pubsub` | Redis, as cache and as pub/sub. |
| `/v1/health/usage` | ClickHouse. |
| `/v1/health/storage` | A test file can be written to and read from the storage device (volume or S3). |
| `/v1/health/storage/local` | The local storage directories are readable and writable. |
| `/v1/health/queue/failed/<queue>` | Failed jobs in a queue, by its Redis name such as `v1-webhooks` or `v1-builds`. Answers `503` at or above `?threshold=` (5000 by default). |
| `/v1/health/certificate?domain=<domain>` | The certificate served on port 443 of a public domain; `validTo` is a Unix timestamp. Fails only once it has expired. |

The checks run on whichever API pod answers, so they show what that pod can
reach.

### Queues

Each queue is a Redis list, `utopia-queue.queue.<name>`; an empty queue has
no key. Print the length of every queue that has jobs waiting:

```console
kubectl -n appwrite exec appwrite-redis-0 -- sh -c \
  'for q in $(redis-cli --scan --pattern "utopia-queue.queue.*"); do echo "$q $(redis-cli llen "$q")"; done'
```

With an external Redis, run the loop with `redis-cli` against it. Queues
that grow without ever draining usually mean no worker consumes them: check
the warning the install notes print
([architecture.md](architecture.md#worker-topologies)).

### Datastores

For the built-in datastores:

```console
kubectl -n appwrite exec appwrite-redis-0 -- redis-cli info memory | grep -E '^(used_memory_human|maxmemory_human)'
kubectl -n appwrite exec appwrite-redis-0 -- redis-cli info stats | grep '^evicted_keys'
kubectl -n appwrite exec appwrite-postgresql-0 -- \
  sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT count(*) FROM pg_stat_activity" -c "SHOW max_connections"'
```

### Scraping the built-in datastores

The chart can run exporters next to the built-in datastores and create
Prometheus Operator objects for them. Nothing is scraped by default.

```yaml
database:
  builtin:
    metrics:
      enabled: true      # postgres_exporter sidecar, port 9187
redis:
  builtin:
    metrics:
      enabled: true      # redis_exporter sidecar, port 9121
clickhouse:
  builtin:
    metrics:
      enabled: true      # ClickHouse's own endpoint, port 9363, no sidecar

metrics:
  serviceMonitor:
    enabled: true        # one ServiceMonitor per datastore with metrics
    labels:
      release: prometheus   # whatever your Prometheus selects on
  prometheusRule:
    enabled: true
    groups:
      - name: appwrite-datastores
        rules:
          - alert: AppwriteRedisDown
            expr: redis_up == 0
            for: 5m
          - alert: AppwritePostgresConnectionsHigh
            expr: sum(pg_stat_activity_count) / max(pg_settings_max_connections) > 0.8
            for: 10m

networkPolicy:
  metrics:
    from:                # with networkPolicy.enabled, who may scrape
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: monitoring
```

Each datastore's Service gets a `metrics` port. `serviceMonitor` and
`prometheusRule` need the Prometheus Operator's CRDs; without them, leave
them off and point your scraper at the Services. With `networkPolicy.enabled`,
the datastores only accept Appwrite pods of the release, plus the sources in
`networkPolicy.metrics.from` on the metrics ports.

External datastores are outside the chart: use your provider's metrics, or
run exporters yourself.

## Example

[`examples/production.yaml`](../examples/production.yaml) puts this list
together: CloudNativePG, an external Redis and ClickHouse, S3, Secrets you
manage, an autoscaled API, grouped workers, a ReadWriteMany volume and
NetworkPolicies. Layer [`examples/aws.yaml`](../examples/aws.yaml) or
[`examples/external-services.yaml`](../examples/external-services.yaml) on
top of it to use other datastores, and
[`examples/functions-existing-secrets.yaml`](../examples/functions-existing-secrets.yaml)
for Functions and Sites.
