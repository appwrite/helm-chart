# External databases

The chart's built-in PostgreSQL, Redis and ClickHouse are single-replica
StatefulSets: good for evaluation and small installs, but without
replication, failover or managed backups. In production, run them as managed
services or with an operator, and point the chart at them.

Each service is switched independently: disable the built-in one and
configure its `external*` block.

## PostgreSQL

```yaml
postgresql:
  enabled: false
externalDatabase:
  adapter: postgresql
  host: appwrite-db.example.internal
  port: 5432
  database: appwrite
  username: appwrite
  existingSecret: appwrite-db      # or password: ...
  passwordKey: db-password
```

Appwrite 2.3.0 uses these PostgreSQL extensions, which Appwrite's own image
(`appwrite/postgres`, PostgreSQL 18) ships:

| Extension | Used for |
| --- | --- |
| `postgis` | spatial attributes |
| `vector` (pgvector) | VectorsDB and embeddings |
| `pg_trgm` | text search |

Your server must provide them, and the Appwrite user must be allowed to
create them, or they must already exist in the database.

### With CloudNativePG

[CloudNativePG](https://cloudnative-pg.io) can run Appwrite's image directly,
which brings the extensions along:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: appwrite-db
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
externalDatabase:
  host: appwrite-db-rw
  existingSecret: appwrite-db-app   # created by CloudNativePG
  passwordKey: password
```

> [!NOTE]
> CloudNativePG expects images that follow its conventions. If yours
> doesn't start, use a CloudNativePG PostGIS image and install pgvector in it,
> or build an image from `appwrite/postgres`.

### Connections

Appwrite opens up to `appwrite.database.connectionsMax` connections in total,
split across `appwrite.database.poolClients` pods. Keep `connectionsMax`
below the server's `max_connections` minus what other clients and replication
need, and `poolClients` at least as large as the number of Appwrite pods. A
connection pooler such as PgBouncer in transaction mode isn't supported:
Appwrite relies on session state.

### MariaDB and MySQL

```yaml
externalDatabase:
  adapter: mariadb    # or mysql
  host: appwrite-db.example.internal
  port: 3306
```

### MongoDB

```yaml
externalDatabase:
  adapter: mongodb
  host: appwrite-mongo.example.internal
  port: 27017
```

Appwrite needs MongoDB to run as a replica set (it uses transactions). Appwrite
connects to a single host with a username and password; it doesn't accept
connection strings, so SRV records and TLS (as MongoDB Atlas uses) aren't
supported in 2.3.0.

### TLS

Appwrite 2.3.0 has no settings for TLS connections to the database. Keep
database traffic on a private network.

## Redis

```yaml
redis:
  enabled: false
externalRedis:
  host: appwrite-redis.example.internal
  port: 6379
  existingSecret: appwrite-redis
  passwordKey: redis-password
```

- Appwrite 2.3.0 connects to a single Redis endpoint: TLS, Sentinel and
  Cluster aren't supported. Valkey works as a drop-in replacement.
- Redis holds the job queues as well as the cache. Size it so it doesn't
  evict queued jobs; with an eviction policy other than `noeviction`, a full
  Redis can drop work.
- `externalRedis.username` sets an ACL user. Appwrite's MQTT server ignores
  it, so use the `default` user when MQTT is enabled.

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
  existingSecret: appwrite-clickhouse
  passwordKey: clickhouse-password
```

Appwrite talks to ClickHouse over HTTP(S) and creates its tables on start.
The password ends up in a connection URL, so it must be URL-safe (or
URL-encoded in the Secret).

## Optional databases

### DocumentsDB

Document databases backed by MongoDB. They need a MongoDB replica set
separate from the main database:

```yaml
appwrite:
  documentsDb:
    enabled: true
    host: appwrite-mongo.example.internal
    existingSecret: appwrite-mongo
    passwordKey: documentsdb-password
```

### VectorsDB

Vector databases backed by PostgreSQL with pgvector. By default they use the
main database when it's PostgreSQL:

```yaml
appwrite:
  vectorsDb:
    enabled: true
    # host: other-postgres.example.internal   # optional separate server
```

## Moving from built-in to external

1. Scale the Appwrite workloads to zero, or stop writes.
2. Dump the built-in database
   (`kubectl exec <release>-postgresql-0 -- pg_dump -U appwrite appwrite`)
   and restore it into the new server.
3. Switch the values as shown above and upgrade.

See [backup-restore.md](backup-restore.md) for dumping each service.
