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
| anything else you changed | `appwrite.config` |

**The encryption key must be identical**, or encrypted data can't be read.

```yaml
appwrite:
  domain: appwrite.example.com
  certificatesEmail: ops@example.com
  secrets:
    existingSecret: appwrite-core   # created from the .env values
```

## 2. Stop the Docker install and dump the database

```console
docker compose stop
docker compose start postgresql          # or mariadb
docker compose exec postgresql pg_dump -U "$_APP_DB_USER" -d "$_APP_DB_SCHEMA" --format=custom > appwrite.dump
```

MariaDB and MongoDB installs keep their engine: point the chart at an external
MariaDB or MongoDB ([external-databases.md](external-databases.md)), or migrate
the data to PostgreSQL with Appwrite's migration tools first.

## 3. Install the chart without starting Appwrite

Install with the API scaled to zero so nothing writes to the new database
before the restore:

```console
helm install appwrite oci://ghcr.io/levivannoort/charts/appwrite -n appwrite --create-namespace \
  -f values.yaml --set api.replicaCount=0 --set workers.combined.replicaCount=0 \
  --set realtime.replicaCount=0 --set tasks.scheduler.enabled=false \
  --set tasks.maintenance.enabled=false --set tasks.interval.enabled=false
```

## 4. Restore the database and files

```console
kubectl -n appwrite exec -i appwrite-postgresql-0 -- \
  sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner' < appwrite.dump
```

Copy the volumes. The Docker volumes are owned by `www-data` (82), which is the
user the chart runs as, so ownership carries over:

```console
# on the Docker host
for v in uploads functions sites builds imports certificates config; do
  docker run --rm -v appwrite_appwrite-$v:/src alpine tar -C /src -cf - . > $v.tar
done
```

Then extract each archive into the matching directory of the `<release>-storage`
volume, for example with a temporary pod that mounts it, or upload them to S3
under `storage/<directory>/` if you switch to S3 storage.

ClickHouse holds only usage history; starting with an empty one is fine.

## 5. Start Appwrite

```console
helm upgrade appwrite oci://ghcr.io/levivannoort/charts/appwrite -n appwrite -f values.yaml --wait
hack/smoke.sh appwrite appwrite   # with SMOKE_EMAIL and SMOKE_PASSWORD of a console admin
```

Then move DNS to the cluster's ingress.
