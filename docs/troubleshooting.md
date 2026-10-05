# Troubleshooting

## Installation

**`appwrite.domain is required` / other "Invalid values" errors.** The chart
checks its values before installing. Each message names the value to change.

**`Refusing to generate a new _APP_OPENSSL_KEY_V1 during an upgrade`.** The
chart Secret is missing. Restore it from your backup, or set
`appwrite.secrets.existingSecret`. With `helm upgrade --dry-run`, use
`--dry-run=server` so Helm can read the existing Secret.

**`No value for ...: provide it explicitly or through an existing Secret`.**
`appwrite.secrets.generate` is `false` and a credential has no source. See
[gitops.md](gitops.md).

**Pods stuck in `Init`.** Init containers wait for dependencies:
`wait-for-datastores` (API) for PostgreSQL, Redis and ClickHouse, and
`wait-for-api` (realtime, workers and tasks) for the API. Check those first:

```console
kubectl -n appwrite logs deploy/appwrite-api -c wait-for-datastores
kubectl -n appwrite logs deploy/appwrite-api
```

**The API takes minutes to become ready on first install.** It creates the
console database, buckets and ClickHouse tables on start. The startup probe
allows six minutes; raise `api.startupProbe.failureThreshold` on slow storage.

**Pods `Pending` with `persistentvolumeclaim ... not found` or
`didn't match pod affinity rules`.** With a ReadWriteOnce `/storage` volume,
every pod that mounts it must run on the same node. Use ReadWriteMany or S3 to
spread them ([storage.md](storage.md)), or give that node enough room.

**Pods rejected by Pod Security admission.** All pods in the Appwrite
namespace pass `restricted`; build Jobs run in their own `baseline` namespace. If
you overrode a security context, check it against the
[restricted profile](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted).

## Requests

**Every request redirects to HTTPS (301).** `appwrite.forceHttps` is on and the
request didn't arrive with `X-Forwarded-Proto: https`. Terminate TLS at the
ingress, or turn `forceHttps` off when nothing in front does TLS.

**Requests return "Router protection does not allow accessing Appwrite over
this domain" (401).** `appwrite.routerProtection` is on and the hostname isn't
`appwrite.domain`, `appwrite.consoleDomain` or a known custom domain.

**The console loads, but API calls fail (404).** Requests to `/v1` must reach
the API, not the console. This is what happens with a `kubectl port-forward`
to the console Service alone: the console sends API calls to its own
address. Route through an ingress controller
([getting-started.md](getting-started.md)), and check your routes with
`hack/routes.sh` ([networking.md](networking.md)).

**Requests fail with 500 for a moment after PostgreSQL restarts.** Appwrite
keeps database connections open; after a restart, the first request on each
stale connection fails (`terminating connection due to administrator
command` in the API log) and Appwrite reconnects. It settles within seconds.

**Realtime disconnects every minute.** The ingress controller or a load
balancer closes idle WebSockets. Raise its idle timeout.

## Background work

**Database attributes stay `processing`; emails or webhooks don't go out.**
The worker that consumes the queue isn't running. Check the worker pods, and
the install notes for a warning about unconsumed queues
([architecture.md](architecture.md#worker-topologies)).

**Scheduled functions run twice.** Two scheduler pods are running, which the
chart prevents unless something scaled the Deployment. Scale it back to 1.

**Custom domains never verify.** `appwrite.domainTargets` must match where the
domain points, and the domain's DNS must have propagated. The interval task
retries every two minutes.

## Functions and Sites

See [executor.md](executor.md#troubleshooting).

## Getting help

Collect the output of:

```console
helm -n appwrite get values appwrite
kubectl -n appwrite get pods,events
kubectl -n appwrite logs deploy/appwrite-api --tail=200
```

and open an issue at <https://github.com/appwrite-labs/helm-chart/issues>
(remove secrets first). Problems in Appwrite itself belong at
<https://github.com/appwrite/appwrite/issues>.
