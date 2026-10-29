# Changelog

All notable changes to the Appwrite Helm chart are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the chart follows [Semantic Versioning](https://semver.org/).
Each release's entries are mirrored into the `artifacthub.io/changes`
annotation in `charts/appwrite/Chart.yaml`.

## [Unreleased]

### Security

- Appwrite 2.6.2, a security release: its base image patches Brotli for
  CVE-2026-111497, and it tightens API keys, realtime, GraphQL, storage,
  VCS and outbound requests ([release notes](https://github.com/appwrite/appwrite/releases/tag/2.6.2)).
  No schema change: the data migration is 2.6.1's.
- Update the Console image to 1.2.108-self-hosted, the one Appwrite 2.6.2
  ships, which patches DOMPurify to 3.4.17 for GHSA-cg2g-xh64-v4q7 and
  GHSA-mrv2-3pqr-j5jr.
- Update the images whose base layers the nightly Trivy scan flags to their
  newest patch releases: Redis 7.4.12-alpine, redis_exporter v1.96.0-alpine,
  SeaweedFS 4.51 and Docker 29.9.2-dind.

### Changed

- The browser 0.3.8 and ExifTool 0.1.1 images, as in Appwrite 2.6.2's
  `docker-compose.yml`.
- `_APP_MEMORY_LIMIT`, new in Appwrite 2.6.2, sets the PHP memory limit of
  every Appwrite process (512M, as before). Raise it, with realtime's memory
  limit, for a realtime that holds thousands of connections ([production.md](docs/production.md#capacity)).
- Project SMTP, messaging SMTP providers and migration sources on a private
  or reserved address need it in `_APP_ALLOWED_INTERNAL_ADDRESSES` from
  Appwrite 2.6.2 on ([networking.md](docs/networking.md#requests-to-private-addresses)).
  The chart's own `smtp` settings aren't affected.
- The console offers Entire as a Git provider ([integrations.md](docs/integrations.md#entire)).
- CI upgrades from the published chart 2.1.0 with default values.

### Added

- The render fails when `compute.secrets.orchestratorSecret` is Appwrite's
  placeholder `your-secret-key`, which Appwrite 2.6.2 refuses for job
  callbacks, unless `compute.secrets.existingSecret` supplies the secret
  instead. An empty value, the default, still generates a random secret.

### Fixed

- The weekly upstream drift check installs PHP, which the gcrunner image
  lacks: it found Appwrite 2.6.2 but failed before opening an issue.
- `make update-images` writes quoted tags such as SeaweedFS's `"4.48"`
  (it reported the bump but left the file unchanged) and runs on macOS's
  bash 3.2, where an anonymous registry pull failed on an unbound variable.

## [2.1.0] - 2026-10-22

Appwrite 2.6.1. Upgrading from 2.0.0: see
[docs/upgrading.md](docs/upgrading.md#to-210).

### Changed

- Appwrite 2.6.1, with console 1.2.97 and the orchestrator's jobs service
  and job sidecar 2.2.4. The console shows the Appwrite version
  (`VITE_APPWRITE_VERSION`).
- The browser is on by default (`browser.enabled`), since Sites are: it
  renders their preview screenshots. Without it, every site deployment logs
  "Screenshot capturing failed" and the console shows no preview.
- The API's startup probe waits for the marker Appwrite 2.6 writes once it
  has created its core schema, so no traffic reaches a pod that would answer
  500 until then.
- The built-in PostgreSQL gets a 1Gi `/dev/shm`, up from 256Mi, as in
  Appwrite's Docker install.
- The combined worker sizes its pools for 79 coroutines, up from 78, for the
  new `maintenance` queue.
- CI upgrades from the published chart 2.0.0 with default values.

### Added

- ExifTool, on by default (`exiftool.enabled`), which removes location,
  camera and capture-time metadata from images uploaded to buckets with
  *Image metadata* stripping on ([optional-components.md](docs/optional-components.md#exiftool)).
- The `maintenance` queue, which cleans up projects nobody used in the last
  30 days: consumed by the combined worker, by `worker-maintenance` in
  `separate` mode, and in `grouped` mode by the group that lists it, or a
  `worker-maintenance` Deployment of its own when none does. With
  `tasks.scheduler.mode: separate`, a `scheduler-maintenance` task schedules
  it ([architecture.md](docs/architecture.md#worker-topologies)).
- `storage.s3.external.pathStyle` (`_APP_STORAGE_S3_PATH_STYLE`), for
  endpoints Appwrite 2.6 can't tell are bucket addresses, such as a custom
  domain ([storage.md](docs/storage.md#your-own-s3-store)). The built-in
  store always uses path-style requests.
- Setup notes for Entire, the Git provider Appwrite 2.6 adds
  ([integrations.md](docs/integrations.md#entire)).
- Troubleshooting for site deployments whose screenshot fails.

## [2.0.0] - 2026-10-14

Appwrite 2.5.0, with Functions and Sites on by default. Upgrading from 1.0.0:
see [docs/upgrading.md](docs/upgrading.md#to-200).

### Changed

- Functions and Sites are on by default: `compute.enabled` and
  `compute.executor.privileged` default to `true`, so a plain install runs
  the executor as a privileged pod in a namespace of its own. Set
  `compute.enabled: false` on clusters that forbid privileged pods.
- Files are stored in object storage by default: `storage.device` defaults
  to `s3`, served by the built-in SeaweedFS. To keep 1.0.0's behaviour, set
  `storage.device: local` and `compute.enabled: false`.
- Appwrite 2.5.0, with console 1.2.74, executor 1.1.2, browser 0.3.6 and
  geo 0.3.2, and the new trusted-proxy, internal-address and DNS settings in
  the environment defaults ([networking.md](docs/networking.md#tls-and-forcehttps)).
- External S3 settings move to `storage.s3.external.endpoint` and
  `storage.s3.external.region`, with `storage.s3.mode: external`. Setting
  the old keys fails with where they went.
- ClickHouse drops its per-second metric, trace and text logs and gives
  tables left behind by a config change a TTL, as Appwrite 2.4.0 does.
- CI upgrades from the published chart 1.0.0 with default values.

### Added

- Built-in object storage: SeaweedFS as a single-replica StatefulSet
  (`storage.s3.mode: builtin`), with generated keys, the bucket created on
  start, and a NetworkPolicy that admits only Appwrite, the orchestrator,
  builds and the executor ([storage.md](docs/storage.md#built-in-object-storage)).
- Troubleshooting for deployments that fail with an internal error while
  Functions and Sites are off.

### Removed

- The assistant: Appwrite removed it in 2.4.0. Setting `assistant.*` fails
  with that message.

### Fixed

- Site screenshots: the browser gets the API Service in `ALLOWED_HOSTS`, as
  browser 0.3.5 and later require for private addresses.
- `make env-defaults` works with Appwrite 2.4.0 and later, and no longer
  leaves an error message in `files/env-defaults.yaml` when it fails.

## [1.0.0] - 2026-10-13

First release of the chart, for Appwrite 2.3.0.

### Added

- The API, console, realtime, workers (combined, separate or grouped),
  schedulers, maintenance and interval tasks, and geo, all passing the
  `restricted` Pod Security Standard.
- Built-in single-replica PostgreSQL, Redis and ClickHouse, or external
  services (PostgreSQL, MariaDB, MySQL, MongoDB; Redis; ClickHouse over HTTP
  or TLS). Each backing service (`database`, `redis`, `clickhouse`,
  `storage`, `smtp`, `documentsDb`, `vectorsDb`) has a `mode` switch, and
  every credential takes the same `{value, secretName, secretKey}` shape.
- Storage on a volume or in S3-compatible object storage.
- Opt-in Functions and Sites in the cluster: builds run as Kubernetes Jobs
  through the open-runtimes orchestrator, in their own `baseline` namespace;
  executions run on the open-runtimes executor on Docker-in-Docker, a
  privileged pod you accept with `compute.executor.privileged` (or Sysbox
  through `runtimeClassName`), in its own namespace behind NetworkPolicies.
- Ingress and Gateway API HTTPRoutes for the API, console, realtime,
  function and site previews, and custom domains.
- Optional browser, assistant, autogravity, embedding and MQTT components.
- PodDisruptionBudgets and topology spread by default; opt-in
  NetworkPolicies, HorizontalPodAutoscalers, and metrics for the built-in
  datastores (exporters, ServiceMonitors and a PrometheusRule).
- Credentials generated once and kept across upgrades and uninstalls, with
  guards against changing the encryption key or regenerating datastore
  passwords. Pods restart when a Secret value they read changes.
- Data migrations on upgrade, a downgrade guard, and a guard against an
  `image.tag` of another Appwrite major version.
- The same extension keys on every component, the built-in datastores
  included (`extraEnv`, `extraVolumes`, `extraVolumeMounts`,
  `extraInitContainers`, `extraContainers`), pod-wide `defaults`, and
  `extraObjects` for your own manifests.
- `values.schema.json`, `helm test` pods, documentation from getting started
  to backups, GitOps and troubleshooting, and example values files for local,
  production, external services, AWS, GCP, Azure, and Functions and Sites
  installs.
