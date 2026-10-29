# External databases

The chart ships its own PostgreSQL, Redis and ClickHouse so that one command
gives you a working install. Each is a single-replica StatefulSet, with no
replication, failover or managed backups: good for evaluation and small
installs. In production, run them as managed services or with an operator,
and point the chart at them.

| Service | Holds | Switch with | Works with |
| --- | --- | --- | --- |
| [PostgreSQL](#postgresql) | projects, users, documents, everything else | `database.mode` | Amazon RDS and Aurora, Cloud SQL, Azure Database for PostgreSQL, CloudNativePG, any PostgreSQL with PostGIS, pgvector and pg_trgm |
| [MariaDB, MySQL](#mariadb-and-mysql), [MongoDB](#mongodb) | the same, instead of PostgreSQL | `database.adapter` | MariaDB or MySQL without required TLS; a MongoDB replica set (not Atlas) |
| [Redis](#redis) | queues, cache, pub/sub, locks | `redis.mode` | ElastiCache, Memorystore, Azure Cache for Redis, Valkey, without TLS |
| [ClickHouse](#clickhouse) | usage statistics, execution logs | `clickhouse.mode` | ClickHouse Cloud, the Altinity operator, any ClickHouse with HTTP(S) |
| [S3](storage.md#s3) | uploads, deployments, builds | `storage.device` | AWS S3, Cloudflare R2, MinIO, SeaweedFS, Hetzner, ... |
| [DocumentsDB](#documentsdb), [VectorsDB](#vectorsdb) | optional database types | `documentsDb`, `vectorsDb` | a MongoDB replica set; PostgreSQL with pgvector |

Each one is switched on its own. You can keep the built-in Redis and
ClickHouse while moving PostgreSQL to RDS, for example.

PostgreSQL, Redis and ClickHouse each have one block in the values, with the
same layout:

```yaml
database:
  mode: external        # builtin (the default) or external
  username: appwrite    # names and credentials: used in both modes
  password:
    secretName: appwrite-external
  external:             # your server: only read with mode external
    host: appwrite-db.example.internal
  # builtin:            # the chart's StatefulSet (image, resources, persistence): only read with mode builtin
```

Every external service follows the same steps:

1. **Create the database or cache**, and a user for Appwrite. Each section
   below has the commands.
2. **Put the password in a Secret** in the Appwrite namespace
   ([credentials](#credentials)).
3. **Set the service's `mode` to `external` and fill in its `external`
   block.** The chart checks the combination before installing and names
   anything that's missing, for example `database.external.host is required
   when database.mode is external.`
4. **Check that the cluster can reach it** ([checking a
   connection](#checking-a-connection)). If you restricted egress with
   `networkPolicy.egress.enabled`, allow the service's address and port in
   `networkPolicy.egress.extraRules` ([security.md](security.md#egress)).

[`examples/external-services.yaml`](../examples/external-services.yaml) and
[`examples/aws.yaml`](../examples/aws.yaml) do all of this in one file each;
layer them over [`examples/minimal.yaml`](../examples/minimal.yaml) or
[`examples/production.yaml`](../examples/production.yaml).

## Credentials

Every password and key in the chart takes the same three fields: `value`,
`secretName` and `secretKey`. An inline `value` works, but it ends up in
your values file. Keep it in a Secret instead:

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

and name it in `secretName`:

```yaml
database:
  password:
    secretName: appwrite-external
```

Leave out the keys for services you don't use. One Secret can serve every
credential, or each can have its own. The key names above are the defaults;
set `secretKey` when yours differ:

| Credential | Default `secretKey` |
| --- | --- |
| `database.password` | `db-password` |
| `redis.password` | `redis-password` |
| `clickhouse.password` | `clickhouse-password` |
| `storage.s3.accessKeyId`, `storage.s3.secretAccessKey` | `s3-access-key`, `s3-secret-key` |
| `smtp.password` | `smtp-password` |
| `documentsDb.password` | `documentsdb-password` |
| `vectorsDb.password` | `vectorsdb-password` |

`secretName` wins over `value`. Secrets from External Secrets, Sealed
Secrets or SOPS work the same way ([gitops.md](gitops.md#credentials)).

The same fields set the built-in services' passwords. With `mode: builtin`,
an empty `database.password`, `redis.password` or `clickhouse.password` is
generated once and kept across upgrades (for Redis, only while
`redis.builtin.requirePassword` is on); set `value` or `secretName` to
choose it yourself.

Appwrite reads credentials when a pod starts. The chart restarts the pods
when an inline `value` changes, but it can't see changes to a Secret you
manage. After changing one, restart them yourself:

```console
kubectl -n appwrite rollout restart deployment -l app.kubernetes.io/instance=appwrite
```

## PostgreSQL

PostgreSQL is the recommended database, and the one the chart tests.

```yaml
database:
  mode: external
  external:
    host: appwrite-db.example.internal
  password:
    secretName: appwrite-external
```

The rest has defaults that fit most servers: `external.port` is 5432,
`adapter` is `postgresql`, and `name` and `username` are both `appwrite`.
Set any that differ on yours.

### Requirements

- **A database and a user that owns it.** Appwrite connects to the database
  named in `database.name` and creates a schema of the same name in it. As an
  administrator (the RDS master user, a Cloud SQL or Azure admin user):

  ```sql
  CREATE USER appwrite WITH PASSWORD '<password>';
  GRANT appwrite TO CURRENT_USER;   -- lets an admin who isn't a superuser assign ownership
  CREATE DATABASE appwrite OWNER appwrite;
  \connect appwrite
  CREATE EXTENSION IF NOT EXISTS postgis;
  CREATE EXTENSION IF NOT EXISTS vector;
  CREATE EXTENSION IF NOT EXISTS pg_trgm;
  ```

- **Extensions.** Appwrite 2.6.2 uses three, which Appwrite's own image
  (`appwrite/postgres`, PostgreSQL 18) ships:

  | Extension | Used for |
  | --- | --- |
  | `postgis` | spatial attributes |
  | `vector` (pgvector) | VectorsDB and embeddings |
  | `pg_trgm` | text search |

  Appwrite runs `CREATE EXTENSION IF NOT EXISTS` for each, so the server must
  offer them, and either they already exist in the database (created as
  above) or the Appwrite user may create them.
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
instance size, so check it against your [connections](#connections) ceiling.

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
      max_connections: "500"          # from your connections ceiling
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
database:
  mode: external
  external:
    host: appwrite-db-rw            # the read-write Service CloudNativePG creates
  password:
    secretName: appwrite-db-app     # the Secret CloudNativePG creates
    secretKey: password
```

> [!NOTE]
> CloudNativePG expects images that follow its conventions. If yours doesn't
> start, use a CloudNativePG PostGIS image and install pgvector in it, or
> build an image from `appwrite/postgres`.

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
certificate, and needs no CA. These variables apply to every PostgreSQL
connection Appwrite makes, including a separate [VectorsDB](#vectorsdb)
server.

## MariaDB and MySQL

```yaml
database:
  mode: external
  adapter: mariadb    # or mysql
  external:
    host: appwrite-db.example.internal
    port: 3306        # the default for both
  password:
    secretName: appwrite-external
```

Create the database first; Appwrite connects to it by name:

```sql
CREATE DATABASE appwrite;
CREATE USER 'appwrite'@'%' IDENTIFIED BY '<password>';
GRANT ALL PRIVILEGES ON appwrite.* TO 'appwrite'@'%';
```

Appwrite connects to MariaDB and MySQL without TLS and has no setting to turn
it on, so a server with `require_secure_transport=ON` rejects it. Keep that
traffic on a private network. VectorsDB needs PostgreSQL, so with MariaDB or
MySQL it needs its own server ([VectorsDB](#vectorsdb)).

## MongoDB

```yaml
database:
  mode: external
  adapter: mongodb
  external:
    host: appwrite-mongo.example.internal
    port: 27017       # the default
  password:
    secretName: appwrite-external
```

- **A replica set.** Appwrite only uses transactions on a replica set. A
  single-member one is enough; Appwrite's Docker install runs one.
- **A user in the `admin` database.** Appwrite authenticates against
  `admin`, so create the user there with access to Appwrite's database:

  ```js
  use admin
  db.createUser({ user: "appwrite", pwd: "<password>", roles: [{ role: "readWrite", db: "appwrite" }] })
  ```

- **One host, no TLS.** Appwrite connects to a single host with a username
  and password. It doesn't take connection strings, so SRV records
  (`mongodb+srv://`) and TLS aren't supported in 2.6.2. That rules out
  MongoDB Atlas.

## Connections

Appwrite opens database connections as it needs them and keeps them open.
`database.connectionsMax` isn't a cap on the total: size the
server's connection limit (`max_connections` on PostgreSQL, MariaDB and
MySQL) from the ceiling worked out here. [architecture.md](architecture.md#database-connections)
explains where it comes from.

**1. Pool size per process.** Every Appwrite process keeps its own pools. Two
of them reach the main database (one for Appwrite's own data, one for
project data), and a third when [VectorsDB](#vectorsdb) uses the main
server. Each pool opens at most:

```text
pool size = max(1, floor(connectionsMax / (poolClients × cpuNum × workerPerCore)), maxCoroutines)
```

| Pods | Processes per pod | `maxCoroutines` |
| --- | --- | --- |
| `api` | `cpuNum` × `appwrite.workerPerCore` (6) | 1 |
| `realtime` | `realtime.processes` (1) | 1 |
| `worker` (`combined`) | 1 | `workers.combined.maxCoroutines` (79) |
| `worker-<queue>` (`separate`) | 1 | the queue's `maxCoroutines` (1 or 8) |
| `worker-<group>` (`grouped`) | the group's `processes` (1) | the group's `maxCoroutines`, by default the sum of its queues' |
| `scheduler`, or `scheduler-*` and `stats-resources` | 1 | 8 |
| `maintenance`, `interval`, `mqtt` | 1 | 1 |

`cpuNum` is the component's `cpuNum` where it has one, else its CPU limit,
else its CPU request, rounded up to a whole CPU.

**2. Ceiling per pod:** processes × pools × pool size.

**3. Add up every pod at peak**, counting autoscalers at `maxReplicas`. The
migration Job that runs during upgrades adds a few more connections.

With the defaults (`connectionsMax` 151, `poolClients` 15, one CPU per pod,
two pools), the middle term of the formula is `floor(151 / (15 × 1 × 6))` = 1:

| Pod | Replicas | Processes | Pool size | Ceiling |
| --- | --- | --- | --- | --- |
| `api` | 1 | 6 | 1 | 12 |
| `realtime` | 1 | 1 | 1 | 2 |
| `worker` | 1 | 1 | 79 | 158 |
| `scheduler` | 1 | 1 | 8 | 16 |
| `maintenance` | 1 | 1 | 1 | 2 |
| `interval` | 1 | 1 | 1 | 2 |
| **Total** | | | | **192** |

From there, each extra API pod adds 12, and each extra worker replica adds
twice its `maxCoroutines`. Raising `connectionsMax` to 270 with
`poolClients` at 20 makes the middle term 2, so each API pod's ceiling
becomes 24.

These are ceilings: a pool only opens another connection when all of its
open ones are busy, so a quiet install holds far fewer. Under sustained load
the pools fill up, and connections stay open once made. Set
`max_connections` to the total plus room for administration, monitoring and
replication. If the server can't take that many:

- Lower `maxCoroutines` on the workers (`workers.combined`, a queue in
  `separate` mode, or a group). Their pools shrink to match; jobs beyond
  that wait for a free connection, and fail if none frees up in time.
- Run fewer API processes per pod, with `appwrite.workerPerCore` or
  `api.cpuNum`, or fewer pods.

Keep `poolClients` at least as large as the number of Appwrite pods at peak
(the install notes warn when it isn't). The built-in PostgreSQL sets
`max_connections` to `connectionsMax + 20` (171 by default); set
`database.builtin.maxConnections` to change it.

## Redis

```yaml
redis:
  mode: external
  external:
    host: appwrite-redis.example.internal
    port: 6379                       # the default
  password:
    secretName: appwrite-external    # leave secretName and value empty for no AUTH
```

### Requirements

- **One endpoint, no TLS.** Appwrite 2.6.2 connects to a single Redis
  endpoint in plain text. TLS, Sentinel and Redis Cluster aren't supported.
  Valkey works as a drop-in replacement.
- **Memory that never runs out.** Redis holds the job queues as well as the
  cache. With an eviction policy such as `allkeys-lru` (what Appwrite's Docker
  install and the built-in Redis use), a full Redis drops queued jobs; with
  `noeviction`, it rejects new ones. Size it with room to spare and alert on
  memory use.
- **ACL users.** `redis.username` sets one. Appwrite's MQTT server
  ignores it, so the chart refuses a username when
  [MQTT](optional-components.md#mqtt) is on; use the `default` user then.

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
default, and use an access key as the password. Microsoft retires Azure Cache
for Redis on 30 September 2028 in favour of Azure Managed Redis. With Managed
Redis, use the non-clustered policy, turn on non-TLS access and access keys,
and connect on port 10000. Neither setup is tested in CI.

## ClickHouse

ClickHouse stores usage statistics and execution logs. Appwrite needs it even
with `appwrite.usageStats` turned off.

```yaml
clickhouse:
  mode: external
  external:
    url: https://abc123.eu-west-1.aws.clickhouse.cloud:8443
  database: appwrite                # the default
  username: appwrite                # the default
  password:
    secretName: appwrite-external
```

### Requirements

- **HTTP or HTTPS.** Appwrite talks to ClickHouse over its HTTP interface,
  not the native protocol. `external.url` is the scheme, host and port only, without
  a path. For an `https://` URL the chart turns on TLS (Appwrite needs
  `?secure=true` in its connection string, and the chart adds it). Without a
  port, `https://` uses 8443 and `http://` 8123.
- **A user with rights on its database.** Appwrite creates its tables on start.

  ```sql
  CREATE DATABASE IF NOT EXISTS appwrite;
  CREATE USER appwrite IDENTIFIED BY '<password>';
  GRANT ALL ON appwrite.* TO appwrite;
  ```

- **A URL-safe password.** It ends up in a connection string unencoded, so use
  only letters, digits, `-`, `_`, `.` and `~`. Characters such as `+`, `%`,
  `@` or `/` corrupt it. This applies to a password from a Secret
  (`secretName`) too, and to the built-in ClickHouse.
  `openssl rand -hex 32` makes a safe one. If you can't change an external
  server's password, store it URL-encoded in the Secret (`%2B` for `+`):
  Appwrite decodes it.

### Managed ClickHouse

**ClickHouse Cloud.** Use the HTTPS endpoint on port 8443 from the service's
*Connect* dialog, and add your cluster's egress IPs to the service's IP
access list.

**Altinity Kubernetes Operator for ClickHouse**, or any self-managed
ClickHouse: point `external.url` at the HTTP Service, for example
`http://clickhouse-appwrite.clickhouse.svc:8123`.

## Optional databases

DocumentsDB and VectorsDB add database types to the console and API. The
chart doesn't deploy a server for either. Their `name`, `username` and
`password` fall back to the main database's when empty, which is rarely
what you want for a separate server, so set them.

### DocumentsDB

Document databases backed by MongoDB. They need a MongoDB replica set,
separate from the main database:

```yaml
documentsDb:
  enabled: true
  host: appwrite-mongo.example.internal
  port: 27017                       # the default
  name: appwrite
  username: appwrite
  password:
    secretName: appwrite-external
    secretKey: documentsdb-password # the default
```

The [MongoDB](#mongodb) requirements apply here too.

### VectorsDB

Vector databases backed by PostgreSQL with pgvector. With `host` empty they
use the main database, which must then be PostgreSQL (the chart refuses
otherwise):

```yaml
vectorsDb:
  enabled: true
```

On the main server they add a pool to its [connection](#connections)
ceiling. To use a separate server:

```yaml
vectorsDb:
  enabled: true
  host: appwrite-vectors.example.internal
  port: 5432                        # the default
  name: appwrite
  username: appwrite
  password:
    secretName: appwrite-external
    secretKey: vectorsdb-password   # the default
```

Give it the same [extensions](#requirements) as the main database: Appwrite's
PostgreSQL client creates all three in every database it sets up.

## Checking a connection

The API's `wait-for-datastores` init container waits until the main
database's, Redis's and ClickHouse's ports accept connections, and prints
which one it's waiting for:

```console
kubectl -n appwrite logs deploy/appwrite-api -c wait-for-datastores
```

An API pod stuck in `Init` means a host isn't reachable from the cluster:
check DNS, security groups, firewall rules and IP allow lists. Realtime, the
workers and the tasks wait for the API, so they stay in `Init` too.

Once the ports are reachable, test the credentials from inside the namespace
with a short-lived Pod. It reads the passwords from your Secret, and its
security context passes the `restricted` Pod Security Standard that
[security.md](security.md#pod-security-standards) recommends for the
namespace. Replace the hosts and URL with yours, and drop the containers for
services you don't use:

```console
kubectl -n appwrite apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: datastore-check
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    runAsGroup: 65534
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: postgresql
      image: postgres:18-alpine
      command: [psql, "host=appwrite-db.example.internal port=5432 user=appwrite dbname=appwrite", -c, "select version()"]
      env:
        - name: PGPASSWORD
          valueFrom: {secretKeyRef: {name: appwrite-external, key: db-password}}
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: [ALL]}
    - name: redis
      image: redis:7-alpine
      command: [redis-cli, -h, appwrite-redis.example.internal, -p, "6379", ping]
      env:
        - name: REDISCLI_AUTH          # drop for a Redis without AUTH
          valueFrom: {secretKeyRef: {name: appwrite-external, key: redis-password}}
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: [ALL]}
    - name: clickhouse
      image: curlimages/curl:8.16.0
      command: [sh, -c, 'curl -sS -u "appwrite:$PASSWORD" "https://abc123.eu-west-1.aws.clickhouse.cloud:8443/?query=SELECT%20version()"']
      env:
        - name: PASSWORD
          valueFrom: {secretKeyRef: {name: appwrite-external, key: clickhouse-password}}
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: [ALL]}
EOF
```

After a few seconds, read the results and remove the Pod:

```console
kubectl -n appwrite logs datastore-check --all-containers --prefix
kubectl -n appwrite delete pod datastore-check
```

Each container prints the server's version, or `PONG` for Redis; anything
else is the error. `psql` uses TLS when the server offers it, as Appwrite
does.

For MariaDB, MySQL or MongoDB, use one of these containers instead of
`postgresql`. `--skip-ssl` matches Appwrite, which doesn't use TLS with
MariaDB and MySQL; the MongoDB check prints the replica set's name.

```yaml
    - name: mariadb
      image: mariadb:11
      command: [mariadb, --skip-ssl, -h, appwrite-db.example.internal, -P, "3306", -u, appwrite, appwrite, -e, "select version()"]
      env:
        - name: MYSQL_PWD
          valueFrom: {secretKeyRef: {name: appwrite-external, key: db-password}}
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: [ALL]}
    - name: mongodb
      image: mongo:8
      command: [sh, -c, 'mongosh --quiet --host appwrite-mongo.example.internal --port 27017 -u appwrite -p "$PASSWORD" --authenticationDatabase admin --eval "db.hello().setName ?? \"not a replica set\""']
      env:
        - name: PASSWORD
          valueFrom: {secretKeyRef: {name: appwrite-external, key: db-password}}
        - name: HOME
          value: /tmp
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: [ALL]}
```

The check Pod isn't covered by the chart's NetworkPolicies. If it works but
Appwrite can't connect, check `networkPolicy.egress`, then the API's log
(`kubectl -n appwrite logs deploy/appwrite-api`), which shows the error.
[Troubleshooting](troubleshooting.md#external-services) has more.

## Moving from built-in to external

This moves the built-in PostgreSQL to an external one. You need `pg_restore`
18 or later on a machine that can reach the new server.

1. Scale the Appwrite workloads to zero
   ([backup-restore.md](backup-restore.md#restoring), step 1).
2. Dump the built-in database, and check which schema its extensions are in:

   ```console
   kubectl -n appwrite exec appwrite-postgresql-0 -- \
     sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-acl' > appwrite.dump
   pg_restore -f - appwrite.dump | grep 'CREATE EXTENSION'
   ```

   With the chart's defaults, Appwrite created them in its own schema,
   `appwrite`, and the dump's tables refer to them there.
3. Prepare an empty database on the new server, as an administrator. Unlike a
   fresh install, create Appwrite's schema and put the extensions in it, as in
   the dump:

   ```sql
   CREATE USER appwrite WITH PASSWORD '<password>';
   GRANT appwrite TO CURRENT_USER;
   CREATE DATABASE appwrite OWNER appwrite;
   \connect appwrite
   CREATE SCHEMA appwrite AUTHORIZATION appwrite;
   CREATE EXTENSION IF NOT EXISTS postgis SCHEMA appwrite;
   CREATE EXTENSION IF NOT EXISTS vector SCHEMA appwrite;
   CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA appwrite;
   ```

4. Restore as the Appwrite user, leaving out what the administrator created
   (the schema, the extensions and PostGIS's `spatial_ref_sys` table, which
   that user may not change):

   ```console
   pg_restore -l appwrite.dump \
     | grep -v -e ' SCHEMA - appwrite ' -e ' EXTENSION ' -e ' spatial_ref_sys ' > appwrite.list
   pg_restore -h appwrite-db.example.internal -U appwrite -d appwrite \
     --no-owner --exit-on-error -L appwrite.list appwrite.dump
   ```

   `--exit-on-error` stops at the first error instead of leaving a partial
   restore behind. If step 2 showed the extensions in `public`, create them
   without `SCHEMA appwrite`, skip `CREATE SCHEMA`, and drop the
   `' SCHEMA - appwrite '` filter.
5. Create the Secret, switch the values as shown in [PostgreSQL](#postgresql)
   and upgrade. The upgrade brings the Deployments back to their replica
   counts; if Helm reports a conflict on `spec.replicas`, see
   [backup-restore.md](backup-restore.md#restoring).
6. Once Appwrite works against the new server, delete the old volume. The
   chart keeps it when `database.mode` changes to `external`:

   ```console
   kubectl -n appwrite delete pvc data-appwrite-postgresql-0
   ```

Redis holds nothing worth copying apart from jobs still in the queues:
switch it in the same window, once the workers have caught up, and Appwrite
rebuilds the cache. For ClickHouse, see
[backup-restore.md](backup-restore.md#clickhouse).
