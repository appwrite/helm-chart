# External databases

The chart ships its own PostgreSQL, Redis and ClickHouse so that one command
gives you a working install. Each is a single-replica StatefulSet, with no
replication, failover or managed backups: good for evaluation and small
installs. In production, run them as managed services or with an operator,
and point the chart at them.

| Service | Holds | Built-in | Bring your own | Works with |
| --- | --- | --- | --- | --- |
| [PostgreSQL](#postgresql) | projects, users, documents, everything else | `postgresql.enabled` | `externalDatabase` | Amazon RDS and Aurora, Cloud SQL, Azure Database for PostgreSQL, CloudNativePG, any PostgreSQL with PostGIS, pgvector and pg_trgm |
| [MariaDB, MySQL](#mariadb-and-mysql), [MongoDB](#mongodb) | the same, instead of PostgreSQL | | `externalDatabase.adapter` | MariaDB or MySQL without required TLS; a MongoDB replica set (not Atlas) |
| [Redis](#redis) | queues, cache, pub/sub, locks | `redis.enabled` | `externalRedis` | ElastiCache, Memorystore, Azure Cache for Redis, Valkey, without TLS |
| [ClickHouse](#clickhouse) | usage statistics, execution logs | `clickhouse.enabled` | `externalClickhouse` | ClickHouse Cloud, the Altinity operator, any ClickHouse with HTTP(S) |
| [S3](storage.md#s3) | uploads, deployments, builds | `/storage` volume | `appwrite.storage.s3` | AWS S3, Cloudflare R2, MinIO, SeaweedFS, Hetzner, ... |

Each one is switched on its own. You can keep the built-in Redis and
ClickHouse while moving PostgreSQL to RDS, for example.

Every external service follows the same three steps:

1. **Create the database or cache**, and a user for Appwrite.
2. **Put the password in a Secret** in the Appwrite namespace
   ([credentials](#credentials)).
3. **Turn off the built-in service and fill in its `external*` block.** The
   chart checks the combination before installing and names anything that's
   missing.

[`examples/external-services.yaml`](../examples/external-services.yaml) and
[`examples/aws.yaml`](../examples/aws.yaml) do all of this in one file each;
layer them over [`examples/minimal.yaml`](../examples/minimal.yaml).

## Credentials

Inline passwords (`password: ...`) work, but they end up in your values file.
Keep them in a Secret instead and name it in `existingSecret`:

```console
kubectl create namespace appwrite
kubectl -n appwrite create secret generic appwrite-external \
  --from-literal=db-password='<PostgreSQL password>' \
  --from-literal=redis-password='<Redis password>' \
  --from-literal=clickhouse-password='<ClickHouse password>' \
  --from-literal=s3-access-key='<access key ID>' \
  --from-literal=s3-secret-key='<secret access key>' \
  --from-literal=smtp-password='<SMTP password>'
```

One Secret can serve every block, or each can have its own. The key names
above are the defaults; change them with the `*Key` value next to each
`existingSecret`:

| Block | Default key | Change it with |
| --- | --- | --- |
| `externalDatabase` | `db-password` | `externalDatabase.passwordKey` |
| `externalRedis` | `redis-password` | `externalRedis.passwordKey` |
| `externalClickhouse` | `clickhouse-password` | `externalClickhouse.passwordKey` |
| `appwrite.storage.s3` | `s3-access-key`, `s3-secret-key` | `accessKeyKey`, `secretKeyKey` |
| `appwrite.smtp` | `smtp-password` | `appwrite.smtp.passwordKey` |
| `appwrite.documentsDb` | `documentsdb-password` | `appwrite.documentsDb.passwordKey` |
| `appwrite.vectorsDb` | `vectorsdb-password` | `appwrite.vectorsDb.passwordKey` |

Secrets from External Secrets, Sealed Secrets or SOPS work the same way
([gitops.md](gitops.md#credentials)). Appwrite reads credentials when a pod
starts. After changing a Secret you manage, restart the pods:

```console
kubectl -n appwrite rollout restart deployment -l app.kubernetes.io/instance=appwrite
```

## PostgreSQL

PostgreSQL is the recommended database, and the one the chart tests.

```yaml
postgresql:
  enabled: false
externalDatabase:
  adapter: postgresql
  host: appwrite-db.example.internal
  port: 5432
  database: appwrite
  username: appwrite
  existingSecret: appwrite-external
  passwordKey: db-password
```

### Requirements

- **Extensions.** Appwrite 2.3.0 uses three, which Appwrite's own image
  (`appwrite/postgres`, PostgreSQL 18) ships:

  | Extension | Used for |
  | --- | --- |
  | `postgis` | spatial attributes |
  | `vector` (pgvector) | VectorsDB and embeddings |
  | `pg_trgm` | text search |

  Your server must offer them, and either the Appwrite user may create them
  or they already exist in the database:

  ```sql
  CREATE EXTENSION IF NOT EXISTS postgis;
  CREATE EXTENSION IF NOT EXISTS vector;
  CREATE EXTENSION IF NOT EXISTS pg_trgm;
  ```

- **A direct connection.** Appwrite relies on session state, so a pooler in
  transaction mode (PgBouncer, Supavisor, RDS Proxy and similar) isn't
  supported. Connect to the server or cluster endpoint.
- **Enough connections.** See [connections](#connections).

### Managed PostgreSQL

The chart's CI tests against Appwrite's own image. The notes below come from
each provider's documentation; they aren't tested in CI.

**Amazon RDS for PostgreSQL and Aurora PostgreSQL.** All three extensions are
available; the master user (`rds_superuser`) can create them. `rds.force_ssl`,
on by default since PostgreSQL 15, needs no changes: Appwrite connects with
TLS when the server offers it ([TLS](#tls)). `max_connections` depends on the
instance size, so check it before setting `connectionsMax`.

**Google Cloud SQL for PostgreSQL.** All three extensions are available;
users created through Cloud SQL belong to `cloudsqlsuperuser` and can create
them. Use the instance's private IP. The *Allow only SSL connections* mode
works as is.

**Azure Database for PostgreSQL (flexible server).** Allow the extensions
first by setting the server parameter `azure.extensions` to
`POSTGIS,VECTOR,PG_TRGM`; `CREATE EXTENSION` fails until you do.
`require_secure_transport`, on by default, needs no changes.

**CloudNativePG** runs in the cluster and can use Appwrite's image directly,
which brings the extensions along:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: appwrite-db
  namespace: appwrite
spec:
  instances: 3
  imageName: docker.io/appwrite/postgres:0.1.0
  postgresql:
    parameters:
      max_connections: "300"
  bootstrap:
    initdb:
      database: appwrite
      owner: appwrite
      postInitApplicationSQL:
        - CREATE EXTENSION IF NOT EXISTS postgis;
        - CREATE EXTENSION IF NOT EXISTS vector;
        - CREATE EXTENSION IF NOT EXISTS pg_trgm;
  storage:
    size: 50Gi
```

```yaml
postgresql:
  enabled: false
externalDatabase:
  host: appwrite-db-rw              # the read-write Service CloudNativePG creates
  existingSecret: appwrite-db-app   # the Secret CloudNativePG creates
  passwordKey: password
```

> [!NOTE]
> CloudNativePG expects images that follow its conventions. If yours doesn't
> start, use a CloudNativePG PostGIS image and install pgvector in it, or
> build an image from `appwrite/postgres`.

### Connections

Appwrite opens up to `appwrite.database.connectionsMax` connections in total,
split across `appwrite.database.poolClients` pods:

- Keep `connectionsMax` below the server's `max_connections`, minus what
  other clients and replication need.
- Keep `poolClients` at least as large as the number of Appwrite pods at
  peak, counting autoscalers at `maxReplicas`. The install notes warn when it
  isn't.

```yaml
appwrite:
  database:
    connectionsMax: 400   # server allows 500
    poolClients: 20       # Appwrite pods at peak
```

### TLS

Appwrite's PostgreSQL client encrypts the connection whenever the server
supports TLS, without checking the server's certificate. That's libpq's
default `sslmode=prefer`, and it covers managed services that require TLS.

To have Appwrite verify the certificate too, set libpq's environment
variables and mount the CA that signed the server's certificate (for RDS, the
[regional bundle](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html);
for Cloud SQL, the instance's server CA):

```console
kubectl -n appwrite create secret generic appwrite-db-ca --from-file=ca.crt=global-bundle.pem
```

```yaml
appwrite:
  extraEnv:
    - name: PGSSLMODE
      value: verify-full          # or verify-ca when the hostname doesn't match the certificate
    - name: PGSSLROOTCERT
      value: /etc/appwrite/db-ca/ca.crt
  extraVolumes:
    - name: db-ca
      secret:
        secretName: appwrite-db-ca
  extraVolumeMounts:
    - name: db-ca
      mountPath: /etc/appwrite/db-ca
      readOnly: true
```

`PGSSLMODE: require` refuses unencrypted connections without checking the
certificate, and needs no CA.

## MariaDB and MySQL

```yaml
postgresql:
  enabled: false
externalDatabase:
  adapter: mariadb    # or mysql
  host: appwrite-db.example.internal
  port: 3306
  existingSecret: appwrite-external
```

Appwrite connects to MariaDB and MySQL without TLS and has no setting to turn
it on, so a server with `require_secure_transport=ON` rejects it. Keep that
traffic on a private network. VectorsDB needs PostgreSQL, so with MariaDB or
MySQL it needs its own server ([VectorsDB](#vectorsdb)).

## MongoDB

```yaml
postgresql:
  enabled: false
externalDatabase:
  adapter: mongodb
  host: appwrite-mongo.example.internal
  port: 27017
  existingSecret: appwrite-external
```

- MongoDB must run as a replica set: Appwrite uses transactions.
- Appwrite connects to one host with a username and password. It doesn't
  take connection strings, so SRV records (`mongodb+srv://`) and TLS aren't
  supported in 2.3.0. That rules out MongoDB Atlas.

## Redis

```yaml
redis:
  enabled: false
externalRedis:
  host: appwrite-redis.example.internal
  port: 6379
  existingSecret: appwrite-external
  passwordKey: redis-password      # leave existingSecret and password empty for no AUTH
```

### Requirements

- **One endpoint, no TLS.** Appwrite 2.3.0 connects to a single Redis
  endpoint in plain text. TLS, Sentinel and Redis Cluster aren't supported.
  Valkey works as a drop-in replacement.
- **Memory that never runs out.** Redis holds the job queues as well as the
  cache. With an eviction policy such as `allkeys-lru` (what Appwrite's Docker
  install and the built-in Redis use), a full Redis drops queued jobs; with
  `noeviction`, it rejects new ones. Size it with room to spare and alert on
  memory use.
- **ACL users.** `externalRedis.username` sets one. Appwrite's MQTT server
  ignores it, so use the `default` user when [MQTT](optional-components.md#mqtt)
  is on.

### Managed Redis

From each provider's documentation; not tested in CI.

**Amazon ElastiCache (Redis OSS or Valkey).** Use a node-based cache with
cluster mode disabled and in-transit encryption off. ElastiCache only allows
an AUTH token together with in-transit encryption, so leave the password
empty and restrict access with security groups. ElastiCache Serverless always
uses TLS and doesn't work.

**Google Memorystore for Redis.** Standard tier for a replica with automatic
failover. AUTH works; in-transit encryption must stay off. The AUTH string
goes in the Secret.

**Azure Cache for Redis.** Turn on the non-TLS port (6379), which is off by
default, and use an access key as the password.

## ClickHouse

ClickHouse stores usage statistics and execution logs. Appwrite needs it even
with `appwrite.usageStats` turned off.

```yaml
clickhouse:
  enabled: false
externalClickhouse:
  url: https://abc123.eu-west-1.aws.clickhouse.cloud:8443
  database: appwrite
  username: appwrite
  existingSecret: appwrite-external
  passwordKey: clickhouse-password
```

### Requirements

- **HTTP or HTTPS.** Appwrite talks to ClickHouse over its HTTP interface,
  not the native protocol. For an `https://` URL the chart turns on TLS
  (Appwrite needs `?secure=true` in its connection string, and the chart adds
  it). Without a port, `https://` uses 8443 and `http://` 8123.
- **A user with rights on its database.** Appwrite creates its tables on start.

  ```sql
  CREATE DATABASE IF NOT EXISTS appwrite;
  CREATE USER appwrite IDENTIFIED BY '<password>';
  GRANT ALL ON appwrite.* TO appwrite;
  ```

- **A URL-safe password.** It ends up in a connection string unencoded, so use
  only letters, digits, `-`, `_`, `.` and `~`. Characters such as `+`, `%`,
  `@` or `/` corrupt it. This applies to a password from `existingSecret`
  too, and to the built-in ClickHouse with `clickhouse.auth.existingSecret`.
  `openssl rand -hex 32` makes a safe one.

### Managed ClickHouse

**ClickHouse Cloud.** Use the HTTPS endpoint on port 8443 from the service's
*Connect* dialog, and add your cluster's egress IPs to the service's IP
access list.

**Altinity Kubernetes Operator for ClickHouse**, or any self-managed
ClickHouse: point `url` at the HTTP Service, for example
`http://clickhouse-appwrite.clickhouse.svc:8123`.

## Optional databases

### DocumentsDB

Document databases backed by MongoDB. They need a MongoDB replica set,
separate from the main database:

```yaml
appwrite:
  documentsDb:
    enabled: true
    host: appwrite-mongo.example.internal
    existingSecret: appwrite-external
    passwordKey: documentsdb-password
```

The [MongoDB](#mongodb) limits apply here too.

### VectorsDB

Vector databases backed by PostgreSQL with pgvector. By default they use the
main database when it's PostgreSQL:

```yaml
appwrite:
  vectorsDb:
    enabled: true
    # host: other-postgres.example.internal   # optional separate server
```

## Checking a connection

The API's `wait-for-datastores` init container waits until every datastore's
port accepts connections, and prints which one it's waiting for:

```console
kubectl -n appwrite logs deploy/appwrite-api -c wait-for-datastores
```

An API pod stuck in `Init` means a host isn't reachable from the cluster:
check DNS, security groups, firewall rules and IP allow lists. Once the port
is reachable, test the credentials from inside the namespace, with the same
network path Appwrite takes:

```console
kubectl -n appwrite run db-check --rm -it --restart=Never --image=postgres:18-alpine -- \
  psql "host=appwrite-db.example.internal user=appwrite dbname=appwrite" -c 'select version()'
kubectl -n appwrite run redis-check --rm -it --restart=Never --image=redis:7-alpine -- \
  redis-cli -h appwrite-redis.example.internal ping
kubectl -n appwrite run ch-check --rm -it --restart=Never --image=curlimages/curl -- \
  curl -sS 'https://abc123.eu-west-1.aws.clickhouse.cloud:8443/?query=SELECT%201' -u appwrite:'<password>'
```

If those work but Appwrite doesn't, the API's log
(`kubectl -n appwrite logs deploy/appwrite-api`) shows the error.
[Troubleshooting](troubleshooting.md#installation) has more.

## Moving from built-in to external

1. Scale the Appwrite workloads to zero
   ([backup-restore.md](backup-restore.md#restoring), step 1).
2. Dump the built-in database and restore it into the new server:

   ```console
   kubectl -n appwrite exec appwrite-postgresql-0 -- \
     sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-acl' > appwrite.dump
   pg_restore -h appwrite-db.example.internal -U appwrite -d appwrite --no-owner appwrite.dump
   ```
3. Switch the values as shown above and upgrade.

Redis holds nothing worth copying apart from jobs still in the queues:
switch it in the same window, once the workers have caught up, and Appwrite
rebuilds the cache. For ClickHouse, see
[backup-restore.md](backup-restore.md#clickhouse).
