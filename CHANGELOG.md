# Changelog

All notable changes to the Appwrite Helm chart are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the chart follows [Semantic Versioning](https://semver.org/).
Each release's entries are mirrored into the `artifacthub.io/changes`
annotation in `charts/appwrite/Chart.yaml`.

## [Unreleased]

First release of the chart, for Appwrite 2.3.0.

### Added

- API, console, realtime, workers, scheduler, maintenance and interval tasks,
  and the geo service, all passing the `restricted` Pod Security Standard.
- Built-in single-replica PostgreSQL, Redis and ClickHouse, or external ones
  (PostgreSQL, MariaDB, MySQL, MongoDB; Redis; ClickHouse over HTTP or TLS).
- Combined, separate and grouped worker topologies; split schedulers.
- Ingress and Gateway API HTTPRoutes for the API, console, realtime, function
  and site previews, and custom domains.
- S3 storage, and Functions and Sites: builds run in the cluster as
  Kubernetes Jobs through the open-runtimes orchestrator, in their own
  `baseline` namespace behind a NetworkPolicy that only allows public
  addresses (plus `deniedCIDRs`). Executions run on the open-runtimes
  executor, by default in the cluster on Docker-in-Docker: a privileged pod
  you accept with `compute.executor.privileged` (or Sysbox through
  `runtimeClassName`), in a namespace of its own with its own copy of its
  credentials, no TCP listener on the Docker daemon, and a NetworkPolicy that
  only lets Appwrite in and the executor out to DNS, S3 and public addresses.
  `compute.executor.mode: external` runs it on a Docker host instead.
- Optional browser, assistant, autogravity, embedding and MQTT components.
- PodDisruptionBudgets and topology spread by default; opt-in
  NetworkPolicies and HorizontalPodAutoscalers.
- Credentials generated once, kept across upgrades and uninstalls, with guards
  against changing the encryption key or regenerating datastore passwords.
- Data migrations as a post-upgrade hook (retried after a failure) or a Job
  named after the version and its spec, and a downgrade guard.
- `values.schema.json` that also accepts a parent chart's `global` values,
  validation of worker topologies and connection limits, `helm test` pods,
  and documentation: getting started, architecture, executor, production,
  networking, security, storage, external databases, optional components,
  migrating from Docker, upgrades, backups, GitOps and troubleshooting.
