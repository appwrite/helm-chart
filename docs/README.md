# Documentation

| Guide | What it covers |
| --- | --- |
| [Getting started](getting-started.md) | Try Appwrite locally, then a first install with HTTPS |
| [Production checklist](production.md) | What to change before going live, with an example values file |
| [Architecture](architecture.md) | Components, startup order, configuration flow, worker topologies |
| [Networking, TLS and domains](networking.md) | Ingress, Gateway API, cert-manager, custom domains |
| [External databases](external-databases.md) | PostgreSQL, MariaDB, MySQL, MongoDB, Redis, ClickHouse |
| [Storage](storage.md) | Volumes, ReadWriteMany, S3 |
| [Functions and Sites](executor.md) | Builds as Jobs and the executor on Docker-in-Docker |
| [Optional components](optional-components.md) | Browser, assistant, autogravity, embedding, MQTT |
| [Security](security.md) | Pod security, credentials, NetworkPolicies, chart signatures |
| [Upgrading](upgrading.md) | Versions, migrations, rollbacks, Helm 4 |
| [Backup and restore](backup-restore.md) | What to back up and how to restore it |
| [Migrating from Docker](migrating-from-docker.md) | Moving an existing Docker Compose install |
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
