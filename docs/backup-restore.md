# Backup and restore

An Appwrite installation keeps state in five places. Back up the first four,
at the same time if you can; Redis needs no backup.

| What | Where | Why it matters |
| --- | --- | --- |
| Credentials | Secret `<fullname>` (or your `existingSecret`s) | `_APP_OPENSSL_KEY_V1` decrypts encrypted data (secrets, OAuth tokens, variables). The built-in datastores' passwords match what's stored on their volumes. |
| Database | PostgreSQL (built-in or external) | Users, projects, documents, everything. |
| Files | `/storage` volume, or the S3 bucket | Bucket files, deployments, builds, certificates. |
| ClickHouse | built-in or external | Usage statistics and the history of function and site executions. Losing it loses that history, not your projects' data. |
| Redis | built-in or external | Queues and cache. Jobs in flight are lost, and a restore flushes it anyway. |

## Credentials

Back up the whole chart Secret once, right after installing, and again after
changing a credential. Keep it somewhere outside the cluster, encrypted:

```console
kubectl -n appwrite get secret appwrite -o yaml > appwrite-secret.yaml
```

The encryption key alone isn't enough to restore the built-in datastores: a
restored PostgreSQL volume still expects the password it was created with.

The chart keeps the Secret when you uninstall (`helm.sh/resource-policy: keep`)
and refuses to generate a new encryption key during an upgrade.

## PostgreSQL

Built-in:

```console
kubectl -n appwrite exec appwrite-postgresql-0 -- \
  sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' > appwrite.dump
```

Restore into an empty database (stop Appwrite first, see below):

```console
kubectl -n appwrite exec -i appwrite-postgresql-0 -- \
  sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' < appwrite.dump
```

For production, prefer continuous backups from your database service or
operator (point-in-time recovery with CloudNativePG, managed snapshots).

## Files

- **S3:** enable versioning or replication on the bucket.
- **Volume:** use volume snapshots (`VolumeSnapshot` with a CSI driver that
  supports them), or a backup tool such as Velero.

## ClickHouse

```console
kubectl -n appwrite exec appwrite-clickhouse-0 -- sh -c \
  "clickhouse-client --user \"\$CLICKHOUSE_USER\" --password \"\$CLICKHOUSE_PASSWORD\" \
    --query \"BACKUP DATABASE appwrite TO S3('https://s3.example.com/backups/appwrite', 'KEY', 'SECRET')\""
```

Restore (with Appwrite stopped, see below) by dropping the database and
restoring it from the same location:

```console
kubectl -n appwrite exec appwrite-clickhouse-0 -- sh -c \
  "clickhouse-client --user \"\$CLICKHOUSE_USER\" --password \"\$CLICKHOUSE_PASSWORD\" \
    --query \"DROP DATABASE IF EXISTS appwrite SYNC\""
kubectl -n appwrite exec appwrite-clickhouse-0 -- sh -c \
  "clickhouse-client --user \"\$CLICKHOUSE_USER\" --password \"\$CLICKHOUSE_PASSWORD\" \
    --query \"RESTORE DATABASE appwrite FROM S3('https://s3.example.com/backups/appwrite', 'KEY', 'SECRET')\""
```

## Restoring

1. Stop writes: note the current replica counts, then scale the Appwrite
   Deployments to zero. The built-in datastores are StatefulSets and keep
   running.

   ```console
   kubectl -n appwrite get deployment -l app.kubernetes.io/instance=appwrite \
     -o jsonpath='{range .items[*]}{.metadata.name}={.spec.replicas}{"\n"}{end}' > replicas.txt
   kubectl -n appwrite scale deployment -l app.kubernetes.io/instance=appwrite --replicas=0
   ```
2. Restore the database, the files and, if you have it, ClickHouse.
3. Make sure the Secret matches the backup: the encryption key, and for the
   built-in datastores their passwords.
4. Flush Redis. Its cache and queued jobs describe the state after the
   backup was taken:

   ```console
   kubectl -n appwrite exec appwrite-redis-0 -- redis-cli FLUSHALL
   ```

   The built-in Redis pod has `REDISCLI_AUTH` set, so no password is needed.
   For an external Redis, flush the database Appwrite uses.
5. Scale the Deployments back to their previous counts:

   ```console
   while IFS== read -r name replicas; do
     kubectl -n appwrite scale deployment "$name" --replicas="$replicas"
   done < replicas.txt
   ```

Scaling back with `helm upgrade` instead isn't reliable with Helm 4: `kubectl
scale` made kubectl the owner of `spec.replicas`, so Helm's server-side apply
reports a conflict ([gitops.md](gitops.md#server-side-apply)). If a later
`helm upgrade` reports one on `spec.replicas`, run it with
`--force-conflicts`. We haven't tested this on every Kubernetes version.
