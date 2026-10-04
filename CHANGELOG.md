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
  (PostgreSQL, MariaDB, MySQL, MongoDB; Redis; ClickHouse over HTTP(S)).
- Combined, separate and grouped worker topologies; split schedulers.
- Ingress and Gateway API HTTPRoutes for the API, console, realtime, function
  and site previews, and custom domains.
- S3 storage, and Functions and Sites through an external open-runtimes
  executor and orchestrator.
- Optional browser, assistant, autogravity, embedding and MQTT components.
- Opt-in NetworkPolicies, PodDisruptionBudgets, HorizontalPodAutoscalers and
  topology spread.
- Credentials generated once, kept across upgrades and uninstalls, with guards
  against changing the encryption key.
- Data migrations as a post-upgrade hook or a version-named Job, and a
  downgrade guard.
- `values.schema.json`, `helm test` pods, and documentation for production,
  networking, storage, external databases, upgrades, backups, GitOps and
  troubleshooting.
