# Getting started

This guide takes you from nothing to a working Appwrite console. Pick the
path that fits:

- [**Try it on your machine**](#try-it-on-your-machine): a local cluster,
  plain HTTP, about ten minutes.
- [**Install on a real cluster**](#install-on-a-real-cluster): your own
  domain, HTTPS through cert-manager.

Both use the chart's built-in PostgreSQL, Redis and ClickHouse. Functions and
Sites need extra infrastructure and come [afterwards](#functions-and-sites).

Examples use the release name `appwrite` in the namespace `appwrite`.

## What you need

- Kubernetes 1.29 or later, with a default StorageClass
- [Helm](https://helm.sh/docs/intro/install/) 4, or Helm 3.18 or later
- `kubectl` pointed at the cluster
- About 2 CPUs and 4 GiB of memory free for Appwrite

Appwrite's console and API share one hostname: requests to `/v1` go to the
API, everything else to the console. Something has to split that traffic,
which is why both paths use an ingress controller. A plain
`kubectl port-forward` to the console isn't enough, because the console
would send its API calls to itself.

## Try it on your machine

This uses [kind](https://kind.sigs.k8s.io) and Traefik. Any local cluster
works; k3d, k3s and Rancher Desktop already include Traefik, so skip step 2
there.

**1. Create a cluster.**

```console
kind create cluster --name appwrite
```

**2. Install an ingress controller.**

```console
helm install traefik traefik --repo https://traefik.github.io/charts \
  --namespace traefik --create-namespace \
  --set service.type=ClusterIP --wait
```

**3. Install Appwrite.**

```console
helm install appwrite oci://ghcr.io/appwrite-labs/charts/appwrite \
  --namespace appwrite --create-namespace \
  --set appwrite.domain=appwrite.localhost \
  --set appwrite.certificatesEmail=you@example.com \
  --set appwrite.forceHttps=false \
  --set ingress.enabled=true \
  --wait --timeout 15m
```

The first start pulls about 2 GB of images and creates the database schema,
so expect a few minutes. `forceHttps=false` is needed because nothing
terminates TLS locally.

**4. Open it.**

```console
kubectl -n traefik port-forward svc/traefik 8080:80
```

Browse to <http://appwrite.localhost:8080>. Browsers resolve any
`*.localhost` name to your own machine, so no DNS setup is needed. Sign up:
the first account becomes the console's administrator, and nobody else can
sign up without an invitation from it.

Create a project, and point an SDK at `http://appwrite.localhost:8080/v1`.

**Clean up** when you're done:

```console
kind delete cluster --name appwrite
```

## Install on a real cluster

### Before you start

- **An ingress controller** with an IngressClass, or a Gateway API
  implementation ([networking.md](networking.md#gateway-api)).
- **[cert-manager](https://cert-manager.io)** with a `ClusterIssuer` for
  Let's Encrypt, here called `letsencrypt`. HTTP-01 is enough for the main
  domain.
- **A DNS record** for your domain, for example `appwrite.example.com`,
  pointing at the ingress controller's load balancer.

### 1. Write a values file

```yaml
# values.yaml
appwrite:
  domain: appwrite.example.com
  certificatesEmail: ops@example.com    # Let's Encrypt account for custom domains

ingress:
  enabled: true
  className: traefik                    # your IngressClass
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
  tls:
    enabled: true                       # certificate in Secret appwrite-tls
  wildcard:
    enabled: false                      # function and site previews; see "Functions and Sites"
```

`appwrite.forceHttps` is on by default: Appwrite redirects HTTP to HTTPS and
generates `https://` links.

To send emails (verification, password recovery, invitations), add SMTP:

```yaml
appwrite:
  smtp:
    host: smtp.example.com
    port: 587
    username: appwrite
    password: <password>                # or existingSecret: <secret name>
  system:
    emailAddress: appwrite@example.com
```

### 2. Install

```console
helm install appwrite oci://ghcr.io/appwrite-labs/charts/appwrite \
  --namespace appwrite --create-namespace \
  -f values.yaml --wait --timeout 15m
```

The chart checks its values first and stops with a message naming anything
that's missing or inconsistent.

### 3. Check it

```console
kubectl -n appwrite get pods
helm test appwrite -n appwrite
kubectl -n appwrite get certificate
```

Every pod should be `Running`, the three tests should pass, and the
certificate should become `Ready` within a minute or two.

### 4. Sign up

Open `https://appwrite.example.com` and create your account. The first
account becomes the console administrator; others need an invitation
(`appwrite.console.whitelistRoot`).

### 5. Back up the encryption key

The chart generated `_APP_OPENSSL_KEY_V1`, which encrypts data at rest.
Without it, a database backup can't be read. Store it somewhere outside the
cluster now:

```console
kubectl -n appwrite get secret appwrite -o jsonpath='{.data._APP_OPENSSL_KEY_V1}' | base64 -d
```

## Functions and Sites

Functions and Sites need S3 storage and the open-runtimes executor. Builds
run in the cluster as Kubernetes Jobs, but the executor starts runtime
containers through a Docker daemon, so it runs on a Docker host next to the
cluster. [executor.md](executor.md) walks through it, including a Docker
Compose file for that host.

Function and site previews use wildcard hostnames (`*.functions.<domain>` and
`*.sites.<domain>`). Turn `ingress.wildcard.enabled` back on then, with a
wildcard certificate from a DNS-01 issuer
([networking.md](networking.md#cert-manager)).

## Next steps

- [Production checklist](production.md): what to change before real users
  depend on it, such as managed databases, S3, replicas and backups.
- [Configuration](../charts/appwrite/README.md#values): every value.
  Appwrite settings without a dedicated value go in `appwrite.config`.
- [Upgrading](upgrading.md) and [backup and restore](backup-restore.md).
- [Troubleshooting](troubleshooting.md).

## Uninstalling

```console
helm uninstall appwrite -n appwrite
```

Helm leaves the data behind on purpose: the Secret with the encryption key
and passwords, and the PersistentVolumeClaims of `/storage` and the
datastores. Installing again with the same release name picks them up.
To remove everything:

```console
kubectl -n appwrite delete secret appwrite
kubectl -n appwrite delete pvc -l app.kubernetes.io/instance=appwrite
```

Delete the Secret and the claims together. A new Secret with an old database
means new passwords for a database that still expects the old ones.
