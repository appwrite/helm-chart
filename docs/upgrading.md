# Upgrading

## Chart and Appwrite versions

Each chart version deploys one Appwrite version, its `appVersion`. Upgrading
the chart upgrades Appwrite; the [changelog](../CHANGELOG.md) says which
Appwrite version each chart ships. You can pin a different Appwrite version
with `image.tag`, but the chart is only tested with its `appVersion` and the
previous minor release.

## What happens during an upgrade

1. Helm applies the new manifests. Pods roll one at a time; the scheduler,
   maintenance and interval tasks are recreated.
2. API pods create any new tables and collections when they start.
3. If the Appwrite version changed, a post-upgrade hook Job runs
   `php app/cli.php migrate`, which migrates every project's data to the new
   version. The upgrade only succeeds once the Job completes; with `--wait`
   Helm waits for it.

The chart records the running Appwrite version in the `appwrite/version`
annotation of the API Deployment, so upgrades that don't change the version
skip the migration.

## Before you upgrade

1. **Back up.** Appwrite migrations can't be rolled back. Take a database
   backup and keep the encryption key; see
   [backup-restore.md](backup-restore.md).
2. **Read the Appwrite release notes** for the versions in between, especially
   for breaking API changes your apps depend on.
3. **Upgrade one minor version at a time** (2.2 → 2.3, not 2.1 → 2.3), as
   Appwrite recommends.

```console
helm upgrade appwrite oci://ghcr.io/levivannoort/charts/appwrite \
  --version <new chart version> -n appwrite -f values.yaml --wait --timeout 30m
```

On large installs the migration can take a long time; raise
`migrations.activeDeadlineSeconds` (default two hours) and `--timeout`.

## Rolling back

`helm rollback` (or `--rollback-on-failure`) restores the previous manifests,
**not the data**. After a migration ran, the previous Appwrite version may not
understand the migrated data. The chart refuses to deploy an older Appwrite
version than the one recorded on the cluster unless
`migrations.allowDowngrade=true`. To go back, restore the backup you took
before upgrading.

## GitOps

Argo CD doesn't run Helm hooks the way Helm does. Use
`migrations.mode: job`: the chart then renders a regular Job named after the
Appwrite version (`<release>-migrate-2-3-0`). Jobs are immutable, so it runs
once per version. Delete old migration Jobs whenever you like.

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
