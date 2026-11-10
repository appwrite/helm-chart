# Security

## Pod Security Standards

Every pod in the Appwrite namespace passes the Kubernetes
[`restricted` Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted),
and CI installs the chart into a namespace that enforces it. (Functions and
Sites add two namespaces of their own: builds under `baseline`, the executor
under `privileged`; see [below](#functions-and-sites).) You can do the same:

```console
kubectl create namespace appwrite
kubectl label namespace appwrite \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted
```

What that means for each pod:

| Setting | Value |
| --- | --- |
| `runAsNonRoot` | `true` |
| `allowPrivilegeEscalation` | `false` |
| `capabilities` | drop `ALL` |
| `seccompProfile` | `RuntimeDefault` |
| `readOnlyRootFilesystem` | `true`; writable paths are `emptyDir` volumes |
| ServiceAccount token | not mounted, except for the orchestrator (`compute.enabled`). Set on each pod, so `serviceAccount.automountServiceAccountToken` doesn't change it. |

| Component | User | Notes |
| --- | --- | --- |
| Appwrite (API, realtime, workers, tasks, MQTT) | `www-data` (82) | API and realtime listen on 8080 (`PORT`). `/tmp`, `/storage/cache` and certbot's directories are `emptyDir`s. |
| Console | `bun` (1000) | |
| Geo | `www-data` (82) | Its port 80 is hard-coded, so the pod sets the namespaced sysctl `net.ipv4.ip_unprivileged_port_start=0`, which `restricted` allows. |
| PostgreSQL | `postgres` (999) | `/var/run/postgresql` is an `emptyDir`. |
| Redis | `redis` (999) | |
| SeaweedFS | 1000 | Runs as root in its own image; the chart sets UID 1000. The S3 users file is written to `/tmp` from the chart's Secret on start. |
| ClickHouse | `clickhouse` (101) | Users and logging come from mounted files, because the image's entrypoint would otherwise write them to `/etc`. Logs go to stdout. |
| Browser | 999 | `/dev/shm` is a memory `emptyDir`. |
| ExifTool | 65532 | Uploads are written to `/tmp` while they're stripped. |
| Autogravity | 65532 | |
| Embedding | 10001 | Models are kept on their own PersistentVolumeClaim. |
| Orchestrator | `nonroot` (65532) | The only pod with a ServiceAccount token, for its Role in the build namespace. |
| Executor | root | In its own namespace. The Docker daemon is privileged; the container that starts the executor is root without capabilities. |

Every security context is a value you can override per component
(`<component>.podSecurityContext`, `<component>.containerSecurityContext`;
for the built-in datastores, under `database.builtin`, `redis.builtin` and
`clickhouse.builtin`). For the Appwrite image, `podSecurityContext` and
`containerSecurityContext` at the top level apply to every component that
doesn't set its own.

### Functions and Sites

Builds run user-supplied build commands, possibly as root, so they can't
pass `restricted`. The chart runs them in a namespace of their own under
`baseline`, which still forbids privileged pods and host access, without
ServiceAccount tokens and behind a NetworkPolicy.

Treat the build namespace as holding secrets:

- The orchestrator writes the key Appwrite uses for build callbacks
  (`orchestrator-secret`) into every build Job, as the pod annotation
  `job.callback.key`. The S3 access and secret keys are in the sidecar's
  environment. Anyone who can read
  pods or Jobs there (the built-in `view` role is enough) gets both. With the
  key they can call the orchestrator's API and send build callbacks to
  Appwrite. Grant access to the build namespace as you would to the chart's
  Secret.
- The `baseline` enforcement label is load-bearing. With the orchestrator's
  key, a caller can ask for build pods with privileged helper containers.
  Only the namespace's Pod Security admission stops them. The chart labels the
  namespace it creates; with `compute.builds.createNamespace: false`, label
  yours `pod-security.kubernetes.io/enforce=baseline` (or `restricted`)
  yourself ([executor.md](executor.md#isolation)).

Executions need a Docker daemon: the
[open-runtimes executor](https://github.com/open-runtimes/executor) starts a
container per runtime. In the cluster the chart gives each executor pod its
own daemon (Docker-in-Docker), which runs as a **privileged container: root
on its node**, and it runs your users' code. That is the one exception to the
standards above. It's on by default (`compute.executor.privileged: true`);
turn it off with `compute.enabled: false`, or run the daemon through Sysbox
instead (`privileged: false` with `runtimeClassName`):

- The executor gets a namespace of its own, the only one labelled for the
  `privileged` standard. The Appwrite namespace stays `restricted` and the
  build namespace `baseline`.
- No ServiceAccount token, and a Secret in its namespace holding only the
  executor secret and the S3 credentials.
- The Docker daemon listens only on a socket inside the pod.
- A NetworkPolicy, on by default, lets only Appwrite pods of the release in,
  and the executor and its runtimes out only to DNS, S3 and public addresses.
- Put it on nodes of its own, with a taint nothing else tolerates: a runtime
  that escapes its container is root on that node, and can read anything
  running there.

Where a privileged pod is unacceptable, Sysbox runs the daemon without it. See
[executor.md](executor.md#executor-isolation).

## Credentials

The chart keeps credentials in a Secret named after the release:

| Key | Set with | Used for |
| --- | --- | --- |
| `_APP_OPENSSL_KEY_V1` | `appwrite.secrets.opensslKey` | Encrypting data at rest and signing JWTs. Losing it makes encrypted data unreadable. |
| `_APP_NOTIFICATIONS_TRACKING_SECRET` | `appwrite.secrets.trackingSecret` | Signing email tracking links. |
| `_APP_GEO_SECRET` | `appwrite.secrets.geoSecret` | Authenticating Appwrite to the geo service. |
| `db-password` | `database.password` | The main database, built-in or external. |
| `redis-password` | `redis.password` | Redis, built-in or external. |
| `clickhouse-password` | `clickhouse.password` | ClickHouse, built-in or external. |
| `documentsdb-password`, `vectorsdb-password` | `documentsDb.password`, `vectorsDb.password` | DocumentsDB and VectorsDB, when they have a password of their own. |
| `executor-secret`, `orchestrator-secret` | `compute.secrets.executorSecret`, `orchestratorSecret` | The executor and the orchestrator (`compute.enabled`). The in-cluster executor gets a copy of `executor-secret` and the S3 keys in a Secret in its namespace. |
| `s3-access-key`, `s3-secret-key` | `storage.s3.accessKeyId`, `storage.s3.secretAccessKey` | S3 storage, built-in or external. Generated once for the built-in store. |
| `smtp-password` | `smtp.password` | SMTP. |

The datastore, S3 and SMTP credentials all take the same three
fields: `value` sets the credential inline and stores it in this Secret;
`secretName` reads it from a Secret you manage instead, under `secretKey`
(the key in the table by default), and leaves it out of this one. These are
generated when nothing provides them:

- the three core keys (`_APP_OPENSSL_KEY_V1`, `_APP_NOTIFICATIONS_TRACKING_SECRET`,
  `_APP_GEO_SECRET`),
- the passwords of the built-in PostgreSQL, Redis and ClickHouse
  (`database.password`, `redis.password` and `clickhouse.password` with
  `mode: builtin`; Redis only with `redis.builtin.requirePassword`, the
  default),
- `executor-secret` and `orchestrator-secret` with `compute.enabled`.

The others exist only when you set them inline. Generated values are 48
random alphanumeric characters. Releases installed before the chart's values
were regrouped keep the built-in PostgreSQL password under
`postgres-password`; the chart reads it from there and stores it as
`db-password` on the next upgrade.

Missing values are generated on install and reused on every upgrade: the chart
reads the existing Secret back with `lookup`. The Secret has
`helm.sh/resource-policy: keep`, so it survives `helm uninstall`, together with
the data it protects. The chart refuses to:

- generate a new `_APP_OPENSSL_KEY_V1` during an upgrade (the Secret is missing),
- change `_APP_OPENSSL_KEY_V1` to a different explicit value, unless
  `appwrite.secrets.allowKeyRotation` is `true`.

**Back up `_APP_OPENSSL_KEY_V1`.**

```console
kubectl -n appwrite get secret appwrite -o jsonpath='{.data._APP_OPENSSL_KEY_V1}' | base64 -d
```

### Bringing your own Secrets

Point each group of credentials at a Secret you manage, for example with
External Secrets, Sealed Secrets or SOPS:

```yaml
appwrite:
  secrets:
    existingSecret: appwrite-core          # keys: _APP_OPENSSL_KEY_V1, _APP_NOTIFICATIONS_TRACKING_SECRET, _APP_GEO_SECRET
    generate: false                        # fail instead of generating anything
database:
  password:
    secretName: appwrite-postgresql        # key: db-password
redis:
  password:
    secretName: appwrite-redis             # key: redis-password
clickhouse:
  password:
    secretName: appwrite-clickhouse        # key: clickhouse-password
storage:
  s3:                                      # the built-in object storage's keys too
    accessKeyId:
      secretName: appwrite-s3              # key: s3-access-key
    secretAccessKey:
      secretName: appwrite-s3              # key: s3-secret-key
compute:                                   # Functions and Sites, on by default
  secrets:
    existingSecret: appwrite-compute       # keys: executor-secret, orchestrator-secret
  executor:
    existingSecret: appwrite-executor      # a copy in the executor namespace (executor.md#existing-secrets)
```

Key names are configurable (`appwrite.secrets.keys.*`, and `secretKey` next
to each `secretName`). External databases, S3 and SMTP take a
`secretName` the same way
([external-databases.md](external-databases.md#credentials) lists their
keys), and integrations can read a Secret through `appwrite.extraEnvFrom`
([integrations.md](integrations.md#passing-settings-and-secrets)).

> [!IMPORTANT]
> Tools that render templates without cluster access (Argo CD, `helm template`)
> can't read the existing Secret, so generated values would change on every
> render. Use existing Secrets and `appwrite.secrets.generate: false` with them;
> see [gitops.md](gitops.md).

## Rotating credentials

To change a credential, set the new value where it comes from: the inline
value (`appwrite.secrets.geoSecret`, `redis.password.value` and so on), your
own Secret, or, for a generated value, the chart's Secret. The chart keeps
whatever it finds there:

```console
kubectl -n appwrite patch secret appwrite --type merge \
  -p '{"stringData":{"redis-password":"<new password>"}}'
```

`helm upgrade` then restarts every pod that reads a changed value of the
chart's Secret: the Appwrite pods (API, realtime, workers, tasks, MQTT), the
orchestrator, the executor, and geo, Redis and ClickHouse,
which each carry a checksum of just the keys they read. PostgreSQL doesn't
need a restart.

| Credential | How |
| --- | --- |
| `_APP_OPENSSL_KEY_V1` | Don't. Appwrite can't re-encrypt existing data with a new key. |
| `_APP_NOTIFICATIONS_TRACKING_SECRET` | Set the new value and upgrade. |
| `_APP_GEO_SECRET` | Set the new value and upgrade. |
| Built-in PostgreSQL password | PostgreSQL only reads `POSTGRES_PASSWORD` when it creates the database. Change the password in PostgreSQL first (below), then set the new value and upgrade. PostgreSQL doesn't need a restart. |
| Built-in Redis password | Set the new value and upgrade. |
| Built-in ClickHouse password | Set the new value and upgrade. |
| `executor-secret`, `orchestrator-secret` | Set the new value and upgrade. With `compute.executor.existingSecret`, change it there too and restart the executor: `kubectl -n appwrite-executor rollout restart deployment/appwrite-executor`. |
| External databases, S3, SMTP, OpenAI | Change it on the service, then set the new value and upgrade. |

Appwrite and a datastore restart at the same time, so expect a short
interruption while both come back with the new value.

To change the built-in PostgreSQL password, open `psql` and use `\password`,
which prompts for the new one:

```console
kubectl -n appwrite exec -it appwrite-postgresql-0 -- \
  sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\password $POSTGRES_USER"'
```

When credentials come from a Secret you manage, nothing restarts on its own:
the checksums only cover the chart's Secret. Restart the release's
Deployments and StatefulSets yourself, and the executor if its credentials
changed:

```console
kubectl -n appwrite rollout restart deployment,statefulset -l app.kubernetes.io/instance=appwrite
```

Don't delete the chart's Secret while keeping the PostgreSQL volume: a new
install would generate a password the existing database doesn't accept. Back
up the whole Secret, not just the encryption key
([backup-restore.md](backup-restore.md)).

## Network policies

`networkPolicy.enabled` is `false` by default. Until you turn it on, nothing
limits traffic to the release's pods: any pod in the cluster can connect to
the built-in PostgreSQL, Redis and ClickHouse (they still ask for their
passwords), to the internal services, and to the API directly. Turn it on,
and restrict the entry points to your ingress controller or Gateway:

```yaml
networkPolicy:
  enabled: true
  ingress:
    from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: traefik
```

NetworkPolicies only take effect with a CNI that enforces them (Calico,
Cilium, kindnet, and most managed offerings).

`networkPolicy.enabled: true` creates these policies in the Appwrite
namespace to limit incoming traffic. "Appwrite pods" are the ones running the
Appwrite image (API, realtime, workers, tasks, MQTT, the migration Job),
which carry the label `appwrite/datastore-client: "true"`.

| Policy | Selects | Allows in |
| --- | --- | --- |
| `<fullname>-edge` | API, console, realtime | `networkPolicy.ingress.from` on the HTTP port (any source when empty); pods of the release on any port |
| `<fullname>-builds-to-api` | API (`compute.enabled`) | build pods, on the HTTP port |
| `<fullname>-internal` | geo, browser, ExifTool, autogravity, embedding | pods of the release |
| `<fullname>-datastores` | PostgreSQL, Redis, ClickHouse | Appwrite pods of the release; on the metrics ports (`database.builtin.metrics.enabled` and the same under `redis` and `clickhouse`), also `networkPolicy.metrics.from` |
| `<fullname>-object-storage` | SeaweedFS (`storage.s3.mode: builtin` with `device: s3`) | Appwrite pods and the orchestrator of the release, build pods and the executor, on the S3 port |
| `<fullname>-background` | workers and tasks | nothing |
| `<fullname>-mqtt` | MQTT broker (`mqtt.enabled`) | `networkPolicy.ingress.from` (any source when empty), on the MQTT ports |
| `<fullname>-orchestrator` | orchestrator (`compute.enabled`) | pods of the release and build pods, on the HTTP port |

Two more limit outgoing traffic:

| Policy | Selects | Allows out |
| --- | --- | --- |
| `<fullname>-browser-egress` | browser (`browser.enabled`) | DNS, the API, and public IPv4 addresses. Private, link-local, CGNAT and other special-purpose ranges are blocked. |
| `<fullname>-egress` | every pod of the release except the browser (`networkPolicy.egress.enabled`) | DNS, pods of the release, the executor (`compute.enabled`), `networkPolicy.egress.extraRules`; see [Egress](#egress) |

`networkPolicy.ingress.from` covers MQTT too. If MQTT clients reach the
broker through a LoadBalancer Service rather than your ingress controller,
add their source to the list (for example an `ipBlock`); that also lets them
reach the HTTP entry points directly.

With Functions and Sites (`compute.enabled`), two more policies are created
in the other namespaces, whether or not `networkPolicy.enabled` is set:

| Policy | Namespace | Allows in | Allows out | Toggle |
| --- | --- | --- | --- | --- |
| `<fullname>-build` | build | nothing | DNS, the API and orchestrator, the built-in object store or the S3 endpoint, public addresses, `extraEgress` | `compute.builds.networkPolicy.enabled` |
| `<fullname>-executor` | executor | Appwrite pods of the release, on port 9900 | DNS, the built-in object store or the S3 endpoint, public addresses, `extraEgress` | `compute.executor.networkPolicy.enabled` |

Both are on by default. [executor.md](executor.md#isolation) explains which
ranges count as public and how to add rules.

All policies that limit egress allow DNS only to `networkPolicy.egress.dns`
on port 53. Clusters that serve DNS on another port or address need more;
see [networking.md](networking.md#networkpolicies-and-dns).

### Egress

Egress is open by default, because Appwrite talks to many external services:
webhooks, SMTP, OAuth and VCS providers, external databases, S3, and the DNS
server it checks custom domains against (`_APP_DNS`). With
`networkPolicy.egress.enabled: true`, every pod of the release except the
browser may reach only DNS, the other pods of the release and the executor.
Add what your installation needs with `extraRules`:

```yaml
networkPolicy:
  enabled: true
  egress:
    enabled: true
    extraRules:
      # SMTP
      - to:
          - ipBlock:
              cidr: 0.0.0.0/0
        ports:
          - port: 587
      # External PostgreSQL
      - to:
          - ipBlock:
              cidr: 10.20.0.0/16
        ports:
          - port: 5432
```

The browser isn't affected: `<fullname>-browser-egress` alone limits it.

With Functions and Sites, the API, workers and orchestrator also need the S3
endpoint, and the orchestrator needs the Kubernetes API server. Both are
outside the release, so add rules for them
([executor.md](executor.md#with-restricted-egress)).

## Verifying chart signatures

Released charts are signed with [cosign](https://github.com/sigstore/cosign)
keyless signing from GitHub Actions, and carry a build provenance attestation.
The release workflow signs with cosign 3, which stores signatures in the new
bundle format, so verify with cosign 3 or later:

```console
cosign verify ghcr.io/appwrite/charts/appwrite:<version> \
  --certificate-identity https://github.com/appwrite/helm-chart/.github/workflows/release.yaml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

gh attestation verify oci://ghcr.io/appwrite/charts/appwrite:<version> \
  --repo appwrite/helm-chart
```
