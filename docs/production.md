# Production checklist

The defaults get Appwrite running with one command. Before real users depend
on it, go through this list.

## Data

- [ ] **Managed or operator-run datastores.** Disable the built-in PostgreSQL,
      Redis and ClickHouse and use replicated services with backups
      ([external-databases.md](external-databases.md)).
- [ ] **Encryption key backed up** outside the cluster, or provided through
      `appwrite.secrets.existingSecret` from your secret manager
      ([security.md](security.md)).
- [ ] **Backups** of the database and files, with a tested restore
      ([backup-restore.md](backup-restore.md)).
- [ ] **S3 storage**, or a ReadWriteMany volume, so API and worker pods can
      spread across nodes ([storage.md](storage.md)).

## Traffic

- [ ] **TLS** at the ingress or Gateway, with `appwrite.forceHttps: true`
      (the default) ([networking.md](networking.md)).
- [ ] **Wildcard certificates** for `*.functions.<domain>` and
      `*.sites.<domain>` if you use Functions or Sites.
- [ ] **`appwrite.domainTargets`** set to your load balancer, so custom
      domains verify.
- [ ] **Body size and timeouts** on the controller suit uploads (30 MB by
      default) and realtime WebSockets.
- [ ] **Client IPs** reach Appwrite in `X-Forwarded-For` and can't be spoofed.

## Capacity

- [ ] **Resources** on every component, sized from real usage. `_APP_CPU_NUM`
      follows them; set `<component>.cpuNum` explicitly when you don't set CPU
      limits.
- [ ] **Replicas and autoscaling** for the API, console and realtime
      (`*.autoscaling.enabled`), with PodDisruptionBudgets (on by default when
      more than one replica can run).
- [ ] **Connection budget:** `appwrite.database.connectionsMax` below the
      database's `max_connections`, and `appwrite.database.poolClients` at least
      the number of Appwrite pods at peak.
- [ ] **Worker topology:** `separate` or `grouped` when one queue (usage,
      builds) shouldn't slow down the others
      ([architecture.md](architecture.md#worker-topologies)).
- [ ] **Redis memory** big enough that it never fills up. The built-in Redis
      evicts least-recently-used keys when full (`allkeys-lru`, as in
      Appwrite's Docker install), and queued jobs are keys too.

## Operations

- [ ] **`appwrite.logFormat: json`** (the default) shipped to your log
      pipeline. Appwrite logs one line per request and job.
- [ ] **Error tracking:** set `_APP_LOGGING_CONFIG` to a Sentry DSN through
      `appwrite.secretConfig`.
- [ ] **SMTP** configured (`appwrite.smtp`), so verification and password
      emails go out.
- [ ] **Console sign-up** restricted: `appwrite.console.whitelistRoot` (the
      default) lets only the first account sign up;
      `appwrite.console.whitelistEmails` and `whitelistIPs` narrow it further.
- [ ] **NetworkPolicies** (`networkPolicy.enabled`), with the entry points
      limited to your ingress controller.
- [ ] **Upgrades** rehearsed on a copy of production
      ([upgrading.md](upgrading.md)).

## Example

```yaml
appwrite:
  domain: appwrite.example.com
  certificatesEmail: ops@example.com
  domainTargets:
    cname: lb.example.com
  secrets:
    existingSecret: appwrite-core
  smtp:
    host: smtp.example.com
    username: appwrite
    existingSecret: appwrite-smtp
  storage:
    device: s3
    s3:
      endpoint: https://s3.example.com
      bucket: appwrite
      existingSecret: appwrite-s3
  database:
    poolClients: 20    # Appwrite pods at peak: 8 API, 2 realtime, 4 workers, 3 tasks

api:
  resources:
    requests: {cpu: "1", memory: 1Gi}
    limits: {memory: 2Gi}
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 8
console:
  replicaCount: 2
realtime:
  replicaCount: 2

workers:
  mode: grouped
  groups:
    core:
      queues: [databases, deletes, mails, messaging, notifications, certificates, migrations, webhooks]
      resources:
        requests: {cpu: 500m, memory: 1Gi}
    usage:
      queues: [stats-usage, stats-resources]
      replicaCount: 2
    compute:
      queues: [builds, jobs, functions, executions, screenshots]

postgresql:
  enabled: false
externalDatabase:
  host: appwrite-db-rw
  existingSecret: appwrite-db-app
  passwordKey: password
redis:
  enabled: false
externalRedis:
  host: appwrite-redis
  existingSecret: appwrite-redis
clickhouse:
  enabled: false
externalClickhouse:
  url: https://clickhouse.example.com:8443
  existingSecret: appwrite-clickhouse

persistence:
  size: 5Gi        # certificates only, with S3

ingress:
  enabled: true
  className: traefik
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
  tls:
    enabled: true
  wildcard:
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-dns01
    tls:
      enabled: true

networkPolicy:
  enabled: true
  ingress:
    from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: traefik
```
