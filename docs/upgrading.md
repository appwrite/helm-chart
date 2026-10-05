# Upgrading

## Chart and Appwrite versions

Each chart version deploys one Appwrite version, its `appVersion`. Upgrading
the chart upgrades Appwrite; the [changelog](../CHANGELOG.md) says which
Appwrite version each chart ships. You can pin a different Appwrite version
with `image.tag`, but the chart is only tested with its `appVersion` and the
previous minor release.

## What happens during an upgrade

1. Helm applies the new manifests. Deployments roll out their new pods; the
   scheduler, maintenance and interval tasks are stopped and recreated.
2. API pods create any new tables and collections when they start.
3. If the Appwrite version changed, a post-upgrade hook Job runs
   `php app/cli.php migrate`, which migrates every project's data to the new
   version. Helm waits for hook Jobs, with or without `--wait`, so the upgrade
   only reports success once the migration has finished.

The chart records the running Appwrite version in the `appwrite/version`
annotation of the API Deployment, so upgrades that don't change the version
skip the migration. The exception is a migration that failed: see
[below](#if-the-migration-fails).

## Before you upgrade

1. **Back up.** Appwrite migrations can't be rolled back. Take a database
   backup and keep the encryption key; see
   [backup-restore.md](backup-restore.md).
2. **Read the Appwrite release notes** for the versions in between, especially
   for breaking API changes your apps depend on.
3. **Don't skip a data migration.** Appwrite's `migrate` applies the
   migration of the version it runs and doesn't replay those of the versions
   in between. Several releases share a migration: every version from 1.9.6
   to 2.3.0 uses the same one, so 2.0 → 2.3 is a single step. Going from
   1.8 to 2.3 isn't: upgrade to a 1.9 release first, then to 2.3. The table
   is in Appwrite's `src/Appwrite/Migration/Migration.php`.

```console
helm upgrade appwrite oci://ghcr.io/appwrite/charts/appwrite \
  --version <new chart version> -n appwrite -f values.yaml --wait --timeout 30m
```

Helm waits for the hook Job for at most `--timeout`, which is 5 minutes when
you don't pass it, far too short for most migrations. On large installs the
migration can take a long time; raise `migrations.activeDeadlineSeconds`
(default two hours) and `--timeout` together. When `--timeout` runs out
first, Helm reports a failure while the migration Job is still running.

## If the migration fails

The upgrade fails and the Job is kept, so you can read why:

```console
kubectl -n appwrite logs job/appwrite-migrate
```

The new Appwrite version is already running at that point. Fix the cause,
then either run `helm upgrade` again or run the migration by hand:

```console
kubectl -n appwrite exec deploy/appwrite-api -- php app/cli.php migrate
```

On the next `helm upgrade`, the chart finds the failed hook Job and runs the
migration again, even though the API Deployment already carries the new
version. This relies on `lookup`, so it only works where Helm talks to the
cluster (the Helm CLI, Flux), not with `helm template` or Argo CD. Once the
migration succeeds, Helm deletes the Job.

## Rolling back

`helm rollback` restores the previous manifests, **not the data**. After a
migration ran, the previous Appwrite version may not understand the migrated
data. To go back to an older Appwrite version, restore the backup you took
before upgrading.

`helm upgrade` refuses to deploy an older Appwrite version than the one
running, unless `migrations.allowDowngrade=true`. The check reads the running
version with `lookup`, so it does nothing with `helm template` or Argo CD.
`helm rollback` doesn't check either: it reapplies stored manifests without rendering the chart. For the
same reason, don't pass `--rollback-on-failure` (`--atomic` in Helm 3) to an
upgrade that changes the Appwrite version: a failed migration would put the
old version back on partly migrated data. Rolling back chart changes that
keep the Appwrite version is safe.

## GitOps

Argo CD doesn't run Helm hooks the way Helm does. Use
`migrations.mode: job`: the chart then renders a regular Job named after the
Appwrite version and a short hash of the Job's spec
(`<fullname>-migrate-2-3-0-<hash>`). As long as the spec stays the same, the
Job stays the same and the migration runs once. Changing the version, or the
Job's resources, environment or scheduling, gives a new Job that runs the
migration again, which is safe because it's idempotent. Delete Jobs of older
versions whenever you like; [gitops.md](gitops.md#migrations) has the details.

With `migrations.mode: none`, run the migration yourself after the new version
is up:

```console
kubectl -n appwrite exec deploy/appwrite-api -- php app/cli.php migrate
```

## Helm 3 to Helm 4

Releases installed with Helm 3 keep working with Helm 4. Helm 4 applies
resources with server-side apply only to releases it installs; for releases
created by Helm 3, pass `--server-side=true` once to switch. Don't change
chart-managed resources with `kubectl edit` in between, or the switch reports
field-manager conflicts.
