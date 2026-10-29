# Migrating from a Docker install

This moves an existing Appwrite Docker Compose installation to the chart,
keeping all data.

Before you start:

- **Same Appwrite version.** The chart deploys Appwrite 2.6.2. Upgrade the
  Docker install to 2.6.2 first, including its data migration. A Docker
  install on 2.2.0 can also move as it is: install the chart with
  `--set image.tag=2.2.0` in step 3 and drop it in step 5, which then runs
  the migration; give that upgrade a `--timeout` long enough for it
  ([upgrading.md](upgrading.md#before-you-upgrade)).
- **PostgreSQL.** The chart's built-in database is PostgreSQL, the Docker
  installer's default. MariaDB and MongoDB installs keep their engine: move
  the data to an external MariaDB or MongoDB with that engine's own tools and
  point the chart at it ([external-databases.md](external-databases.md)),
  and skip the PostgreSQL commands in steps 2 and 4.
- **Storage.** Keep the storage device the Docker install uses. Switching
  between `local` and `s3` during the move breaks the file paths stored in
  the database.
- **Downtime.** Appwrite is unavailable from step 2 until step 5 finishes.

The commands use the release name `appwrite` in namespace `appwrite`, and the
Docker install's directory (usually `appwrite/`, holding
`docker-compose.yml` and `.env`) as the working directory on the Docker host.

## 1. Collect the settings

### Secrets

**The encryption key must be identical**, or encrypted data can't be read.
Put the three core secrets from `.env` in one Secret; with `existingSecret`
set, the chart reads all three from it:

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

Instead of a Secret, you can set `appwrite.secrets.opensslKey`,
`.trackingSecret` and `.geoSecret`; the chart then stores them in its own
Secret.

### Settings

The chart starts from the same defaults as the Docker installer's `.env`, so
only carry over what you changed. Most variables have a value of their own:

| `.env` | Chart |
| --- | --- |
| `_APP_DOMAIN`, `_APP_CONSOLE_DOMAIN` (if set) | `appwrite.domain`, `appwrite.consoleDomain` |
| `_APP_DOMAIN_FUNCTIONS`, `_APP_DOMAIN_SITES` | `appwrite.functionsDomain`, `appwrite.sitesDomain` (default `functions.<domain>`, `sites.<domain>`) |
| `_APP_DOMAIN_TARGET_CNAME`, `_A`, `_AAAA`, `_CAA` | `appwrite.domainTargets.cname`, `.a`, `.aaaa`, `.caa`, set to your load balancer ([networking.md](networking.md#custom-domains)) |
| `_APP_EMAIL_CERTIFICATES` | `appwrite.certificatesEmail` |
| `_APP_OPTIONS_FORCE_HTTPS`, `_APP_OPTIONS_ROUTER_FORCE_HTTPS` | `appwrite.forceHttps` (default `true`) |
| `_APP_OPTIONS_ROUTER_PROTECTION` | `appwrite.routerProtection` |
| `_APP_ROUTER_AUTO_CERTIFICATES` | `appwrite.autoCertificates` (default `false`: TLS ends at the ingress, [networking.md](networking.md#tls-and-forcehttps)) |
| `_APP_CONSOLE_WHITELIST_ROOT`, `_EMAILS`, `_IPS` | `appwrite.console.whitelistRoot`, `.whitelistEmails`, `.whitelistIPs` (lists) |
| `_APP_SYSTEM_EMAIL_NAME`, `_APP_SYSTEM_EMAIL_ADDRESS`, `_APP_EMAIL_SECURITY` | `appwrite.system.emailName`, `.emailAddress`, `.securityEmailAddress` |
| `_APP_SMTP_HOST`, `_PORT`, `_SECURE`, `_USERNAME` | `smtp.host`, `.port`, `.secure`, `.username` (defaults `587` and `tls`) |
| `_APP_SMTP_PASSWORD` | `smtp.password.value`, or `smtp.password.secretName` |
| `_APP_STORAGE_DEVICE` | `storage.device`: `s3` (the chart's default) or `local`, the Docker default: set it explicitly, see below |
| `_APP_STORAGE_S3_ENDPOINT`, `_REGION`, `_BUCKET` | `storage.s3.mode: external` with `storage.s3.external.endpoint`, `.region`, and `storage.s3.bucket` |
| `_APP_STORAGE_S3_ACCESS_KEY`, `_APP_STORAGE_S3_SECRET` | `storage.s3.accessKeyId`, `storage.s3.secretAccessKey`, each with a `value` or a `secretName` |
| `_APP_STORAGE_LIMIT`, `_APP_STORAGE_PREVIEW_LIMIT` | `storage.limit`, `.previewLimit` |
| `_APP_STORAGE_ANTIVIRUS*` | `appwrite.config` ([storage.md](storage.md#antivirus)) |
| `_APP_USAGE_STATS`, `_APP_WORKER_PER_CORE`, `_APP_LOGGING_FORMAT` | `appwrite.usageStats`, `appwrite.workerPerCore`, `appwrite.logFormat` (default `json`) |
| `_APP_DB_SCHEMA` | `database.name`, built-in or external. Keep the same name (default `appwrite`): it's also the name of the schema inside the dump. |
| `_APP_FUNCTIONS_RUNTIMES`, `_APP_SITES_RUNTIMES` | `compute.functionsRuntimes`, `compute.sitesRuntimes` (lists) |
| `_APP_DOCKER_HUB_USERNAME`, `_APP_DOCKER_HUB_PASSWORD` | `OPR_EXECUTOR_DOCKER_HUB_USERNAME` and `_PASSWORD` in `compute.executor.extraEnv` ([executor.md](executor.md#registries)) |
| `_APP_DOCUMENTSDB`, `_APP_VECTORSDB` and their `_APP_DB_*` variables | `documentsDb.*`, `vectorsDb.*` ([external-databases.md](external-databases.md#optional-databases)) |
| OAuth, Git (`_APP_VCS_*`), SMS and other secrets, `_APP_LOGGING_CONFIG` | `appwrite.secretConfig` or `appwrite.extraEnvFrom` ([integrations.md](integrations.md)) |
| other settings you changed: retention, GraphQL limits, function timeouts and sizes, ... | `appwrite.config` |

Leave these out. The chart sets them from its own services and generated
credentials, and a copy in `appwrite.config` would override them:

- `_APP_DB_ADAPTER`, `_APP_DB_HOST`, `_APP_DB_PORT`, `_APP_DB_USER`,
  `_APP_DB_PASS`, `_APP_DB_ROOT_PASS`
- `_APP_REDIS_*`, `_APP_USAGE_PASS`, `_APP_CONNECTIONS_DB_USAGE`,
  `_APP_CONNECTIONS_DB_EXECUTIONS`
- `_APP_EXECUTOR_SECRET`, `_APP_EXECUTOR_HOST`, `_APP_JOBS_SECRET`,
  `_APP_JOBS_HOST`, `_APP_JOBS_ENDPOINT`, `_APP_BUILDS_VOLUME`
- `_APP_GEO_ENDPOINT`, `_APP_MIGRATION_HOST`, `_APP_BROWSER_HOST`,
  `_APP_EXIFTOOL_HOST`, `_APP_AUTOGRAVITY_HOST`, `_APP_STORAGE_S3_PATH_STYLE`

For an external database, Redis or ClickHouse, set `database.mode`,
`redis.mode` or `clickhouse.mode` to `external` and fill in its `external`
settings, username and password instead
([external-databases.md](external-databases.md)).

### Storage devices other than `local` and `s3`

The chart supports the `local` and `s3` storage devices. Appwrite's other
devices (`dospaces`, `backblaze`, `linode`, `wasabi`) are S3-compatible
stores, and Appwrite has deprecated their own variables in favour of
`_APP_STORAGE_S3_*`, which the build orchestrator also needs. Configure them
as `s3` with the provider's endpoint ([storage.md](storage.md#s3)). We haven't
tested that existing files stay readable after the switch; check before you
rely on it.

**Keep the storage device.** The chart stores files in its built-in object
storage by default, while a Docker install keeps them on its volume
(`_APP_STORAGE_DEVICE=local`). Set `storage.device: local` to carry those
files over as described below, and with it `compute.enabled: false`: the
chart's compute plane exchanges code and build output through a bucket and
refuses `local` storage, so functions and sites won't build or run until
storage moves to S3. That move is a migration of its own (the paths stored in
the database change with the device), so plan it separately. A Docker install
already on S3 keeps its bucket (`storage.s3.mode: external`) and Functions
and Sites.

## 2. Stop the Docker install and dump the data

Stop everything, then start only the databases and dump PostgreSQL:

```console
docker compose stop
docker compose start postgresql
docker compose exec -T postgresql \
  sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-acl' > appwrite.dump
```

ClickHouse holds usage statistics and the history of function and site
executions. Starting with an empty one loses that history. To keep it, back
it up to an S3 bucket the cluster can reach as well:

```console
docker compose start clickhouse
docker compose exec -T clickhouse sh -c \
  "clickhouse-client --user \"\$CLICKHOUSE_USER\" --password \"\$CLICKHOUSE_PASSWORD\" \
    --query \"BACKUP DATABASE appwrite TO S3('https://s3.example.com/backups/clickhouse/docker', 'KEY', 'SECRET')\""
```

Copy the file volumes. Docker Compose prefixes volume names with the project
name, usually `appwrite`; the builds volume has a fixed name,
`appwrite-builds`. Check with `docker volume ls`.

```console
for v in uploads functions sites imports certificates config; do
  docker run --rm -v appwrite_appwrite-$v:/src alpine tar -C /src -cf - . > $v.tar
done
docker run --rm -v appwrite-builds:/src alpine tar -C /src -cf - . > builds.tar
```

With S3 storage, the bucket already holds uploads, functions, sites, builds
and imports: point the chart at the same bucket, or copy it with your S3
tooling. Only `certificates` and `config` live on the volume.

## 3. Install the chart without starting Appwrite

Install with the API scaled to zero. Every other Appwrite pod waits for the
API before it starts, so nothing writes to the new database before the
restore:

```console
helm install appwrite oci://ghcr.io/appwrite/charts/appwrite -n appwrite \
  -f values.yaml --set api.replicaCount=0 --set api.autoscaling.enabled=false
```

## 4. Restore the database and files

The new database is empty. `--no-owner` makes the chart's database user own
everything, whatever user the Docker install used:

```console
kubectl -n appwrite exec -i appwrite-postgresql-0 -- \
  sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --exit-on-error' < appwrite.dump
```

To restore ClickHouse, run the `DROP` and `RESTORE` commands in
[backup-restore.md](backup-restore.md#clickhouse) against the path you backed
up to.

Copy the archives to where you run `kubectl`, then extract each into the
matching directory of the `appwrite-storage` claim from a temporary pod. The
pod runs as the user Appwrite runs as (UID 82), so the extracted files belong
to it; the Docker install ran as root, and Appwrite couldn't write to folders
still owned by root. The pod also passes the `restricted` Pod Security
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
same name. With S3 storage, restore only `certificates` and `config`.

## 5. Start Appwrite

Upgrade with your values alone, which drops the overrides from step 3:

```console
helm upgrade appwrite oci://ghcr.io/appwrite/charts/appwrite -n appwrite -f values.yaml --wait
```

Sign in to the console with an existing account and check that projects,
files and functions are there. Then move DNS to the cluster's ingress, and
back up the chart's Secret ([backup-restore.md](backup-restore.md#credentials)).
