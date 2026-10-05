# Migrating from a Docker install

This moves an existing Appwrite Docker Compose installation to the chart,
keeping all data. Both installations must run the same Appwrite version;
upgrade the Docker install first if needed.

Plan for downtime: Appwrite is unavailable from step 2 until the chart is
running.

## 1. Collect the secrets

From the Docker install's `.env`:

| `.env` | Chart |
| --- | --- |
| `_APP_OPENSSL_KEY_V1` | `appwrite.secrets.opensslKey`, or key `_APP_OPENSSL_KEY_V1` of `appwrite.secrets.existingSecret` |
| `_APP_NOTIFICATIONS_TRACKING_SECRET` | `appwrite.secrets.trackingSecret` |
| `_APP_GEO_SECRET` | `appwrite.secrets.geoSecret` |
| `_APP_DOMAIN`, `_APP_CONSOLE_DOMAIN` | `appwrite.domain`, `appwrite.consoleDomain` |
| `_APP_DOMAIN_FUNCTIONS`, `_APP_DOMAIN_SITES` | `appwrite.functionsDomain`, `appwrite.sitesDomain` |
| `_APP_DOMAIN_TARGET_CNAME`, `_A`, `_AAAA`, `_CAA` | `appwrite.domainTargets.cname`, `.a`, `.aaaa`, `.caa` |
| `_APP_DB_SCHEMA` | `postgresql.auth.database` (or `externalDatabase.database`). The schema name inside the dump must match it. |
| `_APP_EMAIL_CERTIFICATES` | `appwrite.certificatesEmail` |
| `_APP_SMTP_*` | `appwrite.smtp.*` |
| `_APP_STORAGE_DEVICE` | `appwrite.storage.device`: `local` or `s3` |
| `_APP_STORAGE_S3_ENDPOINT`, `_REGION`, `_BUCKET` | `appwrite.storage.s3.endpoint`, `.region`, `.bucket` |
| `_APP_STORAGE_S3_ACCESS_KEY`, `_APP_STORAGE_S3_SECRET` | `appwrite.storage.s3.accessKey`, `.secretKey`, or `existingSecret` |
| `_APP_STORAGE_LIMIT`, `_APP_STORAGE_PREVIEW_LIMIT` | `appwrite.storage.limit`, `.previewLimit` |
| `_APP_STORAGE_ANTIVIRUS*` | `appwrite.config` ([storage.md](storage.md#antivirus)) |
| `_APP_EXECUTOR_SECRET`, `_APP_JOBS_SECRET` | `compute.secrets.*` ([executor.md](executor.md)) |
| other secrets you set (OAuth, VCS and SMS keys, `_APP_LOGGING_CONFIG`) | `appwrite.secretConfig` |
| anything else you changed | `appwrite.config` |

The chart supports the `local` and `s3` storage devices. Appwrite's other
devices (`dospaces`, `backblaze`, `linode`, `wasabi`) have no chart values;
set `_APP_STORAGE_DEVICE` and the device's `_APP_STORAGE_<DEVICE>_*`
variables through `appwrite.config` and `appwrite.secretConfig`, which take
precedence over what the chart computes. We haven't tested that.

**Functions and Sites need S3.** The chart's compute plane exchanges code and
build output through a bucket and refuses `compute.enabled` with `local`
storage. A Docker install on local storage can move its files as described
below, but its functions and sites won't build or run in the chart until
storage moves to S3. That move is a migration of its own (the paths stored
in the database change with the device), so plan it separately.

**The encryption key must be identical**, or encrypted data can't be read.
Put the three core secrets in one Secret; with `existingSecret` set, the chart
reads all three from it:

```console
set -a; . ./.env; set +a      # in the Docker install's directory
kubectl create namespace appwrite
kubectl -n appwrite create secret generic appwrite-core \
  --from-literal=_APP_OPENSSL_KEY_V1="$_APP_OPENSSL_KEY_V1" \
  --from-literal=_APP_NOTIFICATIONS_TRACKING_SECRET="$_APP_NOTIFICATIONS_TRACKING_SECRET" \
  --from-literal=_APP_GEO_SECRET="$_APP_GEO_SECRET"
```

```yaml
appwrite:
  domain: appwrite.example.com
  certificatesEmail: ops@example.com
  secrets:
    existingSecret: appwrite-core
```

## 2. Stop the Docker install and dump the database

With PostgreSQL (the default since Appwrite 2.0):

```console
docker compose stop
docker compose start postgresql
docker compose exec -T postgresql \
  sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-acl' > appwrite.dump
```

MariaDB and MongoDB installs keep their engine: the chart's built-in database
is PostgreSQL only. Move the data to an external MariaDB or MongoDB with that
engine's own tools and point the chart at it
([external-databases.md](external-databases.md)), or migrate the data to
PostgreSQL with Appwrite's migration tools first.

## 3. Install the chart without starting Appwrite

Install with the API scaled to zero so nothing writes to the new database
before the restore:

```console
helm install appwrite oci://ghcr.io/appwrite/charts/appwrite -n appwrite --create-namespace \
  -f values.yaml --set api.replicaCount=0 --set workers.combined.replicaCount=0 \
  --set realtime.replicaCount=0 --set tasks.scheduler.enabled=false \
  --set tasks.maintenance.enabled=false --set tasks.interval.enabled=false
```

## 4. Restore the database and files

```console
kubectl -n appwrite exec -i appwrite-postgresql-0 -- \
  sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner' < appwrite.dump
```

Copy the volumes. Docker Compose prefixes volume names with the project name,
usually `appwrite`; the builds volume has a fixed name, `appwrite-builds`.
Check with `docker volume ls`.

```console
# on the Docker host
for v in uploads functions sites imports certificates config; do
  docker run --rm -v appwrite_appwrite-$v:/src alpine tar -C /src -cf - . > $v.tar
done
docker run --rm -v appwrite-builds:/src alpine tar -C /src -cf - . > builds.tar
```

Copy the archives to where you run `kubectl`, then extract each into the
matching directory of the `<fullname>-storage` claim from a temporary pod.
The pod runs as the user Appwrite runs as (UID 82), so the extracted files
belong to it. The Docker install ran as root, and Appwrite couldn't write to
folders still owned by root. It also passes the `restricted` Pod Security
Standard:

```yaml
# storage-restore.yaml
apiVersion: v1
kind: Pod
metadata:
  name: storage-restore
  namespace: appwrite
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 82
    runAsGroup: 82
    fsGroup: 82
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: restore
      image: alpine:3
      command: [sleep, infinity]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: [ALL]}
      volumeMounts:
        - {name: storage, mountPath: /storage}
  volumes:
    - name: storage
      persistentVolumeClaim:
        claimName: appwrite-storage
```

```console
kubectl apply -f storage-restore.yaml
kubectl -n appwrite wait --for=condition=Ready pod/storage-restore
for d in uploads functions sites imports certificates config builds; do
  kubectl -n appwrite exec -i storage-restore -- \
    sh -c "mkdir -p /storage/$d && tar -C /storage/$d -xf -" < $d.tar
done
kubectl -n appwrite delete pod storage-restore
```

The API and workers mount each directory of the claim as a `subPath` with the
same name. With S3 storage, only `certificates` and `config` live on the
volume; copy the bucket with your S3 tooling instead.

Keep the storage device the Docker install used (`local` or `s3`). Switching
during the move breaks the file paths stored in the database.

ClickHouse holds usage statistics and the history of function and site
executions. Starting with an empty one loses that history. To keep it, back
up the `appwrite` database in the Docker install's ClickHouse and restore it
into the chart's ([backup-restore.md](backup-restore.md#clickhouse)).

## 5. Start Appwrite

```console
helm upgrade appwrite oci://ghcr.io/appwrite/charts/appwrite -n appwrite -f values.yaml --wait
```

Sign in to the console with an existing account and check that projects,
files and functions are there. Then move DNS to the cluster's ingress.
