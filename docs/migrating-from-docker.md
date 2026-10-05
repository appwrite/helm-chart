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
| `_APP_EMAIL_CERTIFICATES` | `appwrite.certificatesEmail` |
| `_APP_SMTP_*` | `appwrite.smtp.*` |
| `_APP_STORAGE_*` | `appwrite.storage.*` |
| `_APP_EXECUTOR_SECRET`, `_APP_JOBS_SECRET` | `compute.secrets.*` ([executor.md](executor.md)) |
| other secrets you set (OAuth, VCS and SMS keys, `_APP_LOGGING_CONFIG`) | `appwrite.secretConfig` |
| anything else you changed | `appwrite.config` |

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

```console
docker compose stop
docker compose start postgresql          # or mariadb
docker compose exec -T postgresql \
  sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-acl' > appwrite.dump
```

MariaDB and MongoDB installs keep their engine: point the chart at an external
MariaDB or MongoDB ([external-databases.md](external-databases.md)), or migrate
the data to PostgreSQL with Appwrite's migration tools first.

## 3. Install the chart without starting Appwrite

Install with the API scaled to zero so nothing writes to the new database
before the restore:

```console
helm install appwrite oci://ghcr.io/appwrite-labs/charts/appwrite -n appwrite --create-namespace \
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

Extract each archive into the matching directory of the `<fullname>-storage`
volume, for example from a temporary pod that mounts it, and hand the files
to the user the chart runs as (UID 82). The Docker install runs as root, so
without this Appwrite can't write to folders it created there:

```console
tar -C /storage/<directory> -xf <directory>.tar
chown -R 82:82 /storage/<directory>
```

Keep the storage device the Docker install used (`local` or `s3`). Switching
during the move breaks the file paths stored in the database.

ClickHouse holds usage statistics and the history of function and site
executions. Starting with an empty one loses that history. To keep it, back
up the `appwrite` database in the Docker install's ClickHouse and restore it
into the chart's ([backup-restore.md](backup-restore.md#clickhouse)).

## 5. Start Appwrite

```console
helm upgrade appwrite oci://ghcr.io/appwrite-labs/charts/appwrite -n appwrite -f values.yaml --wait
```

Sign in to the console with an existing account and check that projects,
files and functions are there. Then move DNS to the cluster's ingress.
