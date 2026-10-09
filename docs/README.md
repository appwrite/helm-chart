# Documentation

New to the chart? Start with [Getting started](getting-started.md), then work
through the [production checklist](production.md) before real users depend
on the install. Ready-made values files are in [`examples/`](../examples).

## Start

| Guide | What it covers |
| --- | --- |
| [Getting started](getting-started.md) | Try Appwrite locally, then a first install with HTTPS |
| [Production checklist](production.md) | What to change before going live |
| [Migrating from Docker](migrating-from-docker.md) | Moving an existing Docker Compose install |

## Connect your own services

The chart runs everything Appwrite needs by default. Each piece can be
swapped for a managed service or one you already run:

| Service | Built-in | Bring your own | Guide |
| --- | --- | --- | --- |
| PostgreSQL (or MariaDB, MySQL, MongoDB) | StatefulSet | RDS, Cloud SQL, Azure, CloudNativePG, ... | [External databases](external-databases.md#postgresql) |
| Redis | StatefulSet | ElastiCache, Memorystore, Azure Cache, Valkey | [External databases](external-databases.md#redis) |
| ClickHouse | StatefulSet | ClickHouse Cloud, Altinity operator | [External databases](external-databases.md#clickhouse) |
| File storage | PersistentVolumeClaim | S3, R2, GCS, Spaces, MinIO, ... | [Storage](storage.md#s3) |
| Email | none | any SMTP server: SES, SendGrid, Postmark, ... | [Integrations](integrations.md#email-smtp) |
| Git deployments, console OAuth, SMS, Sentry | none | GitHub, GitLab, Gitea, Bitbucket, Twilio, ... | [Integrations](integrations.md) |
| TLS certificates | none | cert-manager, or your own | [Networking](networking.md#tls-and-forcehttps) |

## Configure

| Guide | What it covers |
| --- | --- |
| [Networking, TLS and domains](networking.md) | Ingress, Gateway API, cert-manager, custom domains |
| [External databases](external-databases.md) | PostgreSQL, MariaDB, MySQL, MongoDB, Redis, ClickHouse |
| [Storage](storage.md) | Volumes, ReadWriteMany, S3 |
| [Email, Git and other integrations](integrations.md) | SMTP, GitHub App, console sign-in, SMS, Sentry |
| [Functions and Sites](executor.md) | Builds as Jobs and the executor on Docker-in-Docker |
| [Optional components](optional-components.md) | Browser, assistant, autogravity, embedding, MQTT |
| [Security](security.md) | Pod security, credentials, NetworkPolicies, chart signatures |
| [Every value](../charts/appwrite/README.md#values) | The generated reference of `values.yaml` |

## Operate

| Guide | What it covers |
| --- | --- |
| [Architecture](architecture.md) | Components, startup order, configuration flow, worker topologies |
| [Upgrading](upgrading.md) | Versions, migrations, rollbacks, Helm 4 |
| [Backup and restore](backup-restore.md) | What to back up and how to restore it |
| [GitOps](gitops.md) | Argo CD and Flux |
| [Troubleshooting](troubleshooting.md) | Common problems and what to check |

## Conventions

Examples use the release name `appwrite` in the namespace `appwrite`.
Resource names start with the chart's *fullname*, written `<fullname>` in
these guides: the release name when it contains `appwrite`, otherwise
`<release>-appwrite`. A release called `appwrite` creates the Secret
`appwrite` and the Service `appwrite-api`; a release called `prod` creates
`prod-appwrite` and `prod-appwrite-api`. Set `fullnameOverride` to choose the
prefix yourself.
