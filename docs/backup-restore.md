# Backup and restore

An Appwrite installation keeps state in five places. Back up all of them, at
the same time if you can.

| What | Where | Why it matters |
| --- | --- | --- |
| Encryption key | Secret `<release>`, key `_APP_OPENSSL_KEY_V1` (or your `existingSecret`) | Without it, encrypted data (secrets, OAuth tokens, variables) can't be read. |
| Database | PostgreSQL (built-in or external) | Users, projects, documents, everything. |
| Files | `/storage` volume, or the S3 bucket | Bucket files, deployments, builds, certificates. |
| ClickHouse | built-in or external | Usage statistics and execution logs. Losing it loses history, not data. |
| Redis | built-in or external | Queues and cache. Jobs in flight are lost; no need to back it up. |

## Encryption key

Back it up once, right after installing, somewhere outside the cluster:

```console
kubectl -n appwrite get secret appwrite -o jsonpath='{.data._APP_OPENSSL_KEY_V1}' | base64 -d
```

The chart keeps the Secret when you uninstall (`helm.sh/resource-policy: keep`)
and refuses to generate a new key during an upgrade.

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

## Restoring

1. Stop writes: scale the Appwrite Deployments to zero. The built-in
   datastores are StatefulSets and keep running.

   ```console
   kubectl -n appwrite scale deployment -l app.kubernetes.io/instance=appwrite --replicas=0
   ```
2. Restore the database, the files and, if you have it, ClickHouse.
3. Make sure the Secret holds the encryption key from the backup.
4. `helm upgrade` with your usual values. This scales everything back up.
