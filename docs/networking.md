# Networking, TLS and domains

Appwrite's Docker install puts Traefik in front of everything. On Kubernetes
the chart creates the same routes for your ingress controller or Gateway.

## Routes

| Hostname | Path | Goes to |
| --- | --- | --- |
| `appwrite.domain` (and `appwrite.consoleDomain`) | `/v1/realtime` | realtime (WebSocket) |
| | `/v1`, `/.well-known` | API |
| | everything else | console (the API with `console.enabled: false`) |
| `*.<appwrite.functionsDomain>`, `*.<appwrite.sitesDomain>` | everything | API (function and site previews) |
| any other hostname | everything | API (custom domains), off by default |

`appwrite.functionsDomain` and `appwrite.sitesDomain` default to
`functions.<domain>` and `sites.<domain>`.

Every route goes to a ClusterIP Service, on port 80 unless you change
`<component>.service.port`. Pick one of the two mechanisms below.

## Ingress

```yaml
appwrite:
  domain: appwrite.example.com
ingress:
  enabled: true
  className: traefik
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt          # HTTP-01, main domain
  tls:
    enabled: true            # secret: <fullname>-tls
  wildcard:
    enabled: true
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-dns01  # wildcards need DNS-01
    tls:
      enabled: true          # secret: <fullname>-wildcard-tls
  customDomains:
    enabled: false
```

`ingress.annotations` applies to every Ingress, and the per-Ingress
annotations are merged over it. Without the override on
`ingress.wildcard.annotations`, the wildcard Ingress inherits the HTTP-01
issuer and its certificate never becomes ready.

This creates up to three Ingresses, so they can carry different annotations
and certificates:

| Ingress | Hosts | TLS secret |
| --- | --- | --- |
| `<fullname>` | `appwrite.domain`, `appwrite.consoleDomain` | `ingress.tls.secretName` (default `<fullname>-tls`) |
| `<fullname>-wildcard` | `*.<functionsDomain>`, `*.<sitesDomain>` | `ingress.wildcard.tls.secretName` (default `<fullname>-wildcard-tls`) |
| `<fullname>-custom-domains` (`ingress.customDomains.enabled`) | a rule without a host | none |

> [!WARNING]
> The custom-domains Ingress has no host, so it matches every hostname that
> no other Ingress of its class claims. On a shared IngressClass, that makes
> Appwrite's API the catch-all for the whole cluster: a typo in another
> team's hostname, or any DNS name pointed at the controller, lands on
> Appwrite. All three Ingresses use `ingress.className`, so give Appwrite an
> IngressClass (and controller) of its own, or use the Gateway API with a
> dedicated listener ([Custom domains](#custom-domains)).
> `appwrite.routerProtection: true` also helps: Appwrite then rejects
> hostnames that are neither its own nor a custom domain added to a project.

The chart adds no controller-specific annotations. Add what your controller
needs through `ingress.annotations` (all three), `ingress.wildcard.annotations`
or `ingress.customDomains.annotations`. Two more settings cover controllers
with their own habits:

- `ingress.pathType` (default `Prefix`): some controllers, such as GCE, need
  `ImplementationSpecific` for prefix matching.
- `ingress.extraTls`: extra `spec.tls` entries on the main Ingress, for
  example a certificate that also covers other hosts.

> [!NOTE]
> The community ingress-nginx controller was retired in March 2026. The chart
> works with any conformant Ingress controller; new installs should prefer the
> Gateway API.

## Gateway API

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: public
      namespace: gateway
      sectionName: https-appwrite
  wildcard:
    enabled: true
    parentRefs:
      - name: public
        namespace: gateway
        sectionName: https-functions
      - name: public
        namespace: gateway
        sectionName: https-sites
```

This creates up to three HTTPRoutes (`<fullname>`, `<fullname>-wildcard`,
`<fullname>-custom-domains`) that mirror the Ingresses. TLS is configured on
the Gateway's listeners, for example:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: public
  namespace: gateway
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-dns01
spec:
  gatewayClassName: example
  listeners:
    - name: https-appwrite
      hostname: appwrite.example.com
      port: 443
      protocol: HTTPS
      tls:
        certificateRefs: [{name: appwrite-tls}]
      allowedRoutes:
        namespaces: {from: All}
    - name: https-functions
      hostname: "*.functions.appwrite.example.com"
      port: 443
      protocol: HTTPS
      tls:
        certificateRefs: [{name: appwrite-functions-tls}]
      allowedRoutes:
        namespaces: {from: All}
    - name: https-sites
      hostname: "*.sites.appwrite.example.com"
      port: 443
      protocol: HTTPS
      tls:
        certificateRefs: [{name: appwrite-sites-tls}]
      allowedRoutes:
        namespaces: {from: All}
```

The wildcard HTTPRoute carries both `*.functions` and `*.sites` hostnames. A
route only attaches to listeners whose hostname matches, so it needs a parent
reference for each listener; with only one, the other set of previews gets
no route.

`httpRoute.hostnameHeaderMatch: true` reproduces one more Traefik rule:
requests carrying an `x-appwrite-hostname` header go to the API instead of the
console. It uses a `RegularExpression` header match, which is an extended
Gateway API feature. Traefik and Envoy Gateway implement it; check yours
before you turn it on, because a Gateway that doesn't will reject the route.

## TLS and `forceHttps`

`appwrite.forceHttps` (on by default) makes Appwrite redirect plain HTTP to
HTTPS and generate `https://` URLs. Appwrite decides whether a request was
HTTPS from the `X-Forwarded-Proto` header, which ingress controllers and
Gateways set. Turn it off only when nothing in front of Appwrite terminates TLS.

The chart's probes and in-cluster calls send the API Service's DNS name,
`<fullname>-api.<namespace>.svc`, as the `Host` header. Appwrite treats it as
internal (`_APP_MIGRATION_HOST`), so they aren't redirected. Because the
custom-domains route forwards any hostname, a client that sends this `Host`
header from outside reaches the API over plain HTTP too. If that matters,
redirect HTTP to HTTPS at the edge for unknown hostnames, keeping
`/.well-known/acme-challenge/` on HTTP for custom-domain certificates.

Appwrite takes the client IP from the headers in `_APP_TRUSTED_HEADERS`
(default `x-forwarded-for`), but only on connections from a proxy in
`_APP_TRUSTED_PROXIES`, and then the rightmost address in the header that
isn't itself a trusted proxy. The default trusts loopback, the RFC 1918
ranges and `100.64.0.0/10`, which covers the pod network of most clusters, so
the ingress controller or Gateway in front of Appwrite is trusted as it is.
Set your own list through `appwrite.config` when pods get other addresses
(IPv6 or dual-stack clusters), or when a load balancer or CDN in front of the
controller adds its own address to the header:

```yaml
appwrite:
  config:
    _APP_TRUSTED_PROXIES: "10.0.0.0/8,fd00::/8"   # replaces the default
```

Make sure your controller sets the header, and that clients can't spoof it.

### Requests to private addresses

Appwrite refuses to fetch a URL that resolves to a private or reserved
address: OAuth2 and OIDC providers, webhooks, messaging webhooks, migration
sources and avatar URLs. From 2.6.2 on, it refuses the same addresses for
the SMTP servers projects and messaging providers set (not the chart's own
`smtp`). That includes every pod and Service in the cluster. To use an
identity provider, webhook receiver or mail server that runs in the
cluster, list its addresses (IPs or CIDRs, comma-separated) in
`_APP_ALLOWED_INTERNAL_ADDRESSES`, for example your Service range:

```yaml
appwrite:
  config:
    _APP_ALLOWED_INTERNAL_ADDRESSES: "10.96.0.0/12"
```

Migrations from this Appwrite itself are allowed already
(`_APP_MIGRATION_HOST`). Before connecting to a migration source, an avatar
URL or a project's SMTP server, Appwrite also checks its host through the
resolvers in `_APP_DNS_EXTERNAL` (by default `_APP_DNS`, `8.8.8.8`) rather
than the cluster's DNS. With `networkPolicy.egress.enabled`, that resolver needs the
same egress rule as custom domains below.

### cert-manager

- **Main domain:** HTTP-01 works. Annotate the main Ingress (or the Gateway)
  with your issuer, for example
  `cert-manager.io/cluster-issuer: letsencrypt`.
- **Preview wildcards** (`*.<functionsDomain>`, `*.<sitesDomain>`): wildcard
  certificates need DNS-01. Put the DNS-01 issuer on
  `ingress.wildcard.annotations`, as in the [Ingress](#ingress) example; it
  overrides the issuer from `ingress.annotations`. With the Gateway API, the
  issuer goes on the Gateway, and both preview listeners need certificates
  from a DNS-01 issuer.
- `appwrite.autoCertificates` stays `false`, so Appwrite doesn't try to issue
  certificates for preview subdomains itself.

## Custom domains

Projects, functions and sites can use custom domains. Appwrite:

1. checks the domain's DNS against `appwrite.domainTargets` (CNAME, A, AAAA,
   CAA), so set these to what users should point their records at, usually
   your load balancer's hostname and IPs;
2. asks Let's Encrypt for a certificate with an HTTP-01 challenge. The
   certificates worker writes the challenge to `/storage/certificates` and
   the API serves it from there;
3. stores the certificate in `/storage/certificates/<domain>` and writes a
   Traefik configuration file to `/storage/config`.

On Kubernetes, steps 1 and 2 work when HTTP traffic for unknown hostnames
reaches the API: enable `ingress.customDomains` or `httpRoute.customDomains`
and make sure port 80 isn't redirected before the request reaches Appwrite.
The worker and the API must share `/storage`, so keep `storage.volume.enabled`,
also with S3 ([storage.md](storage.md#the-volume-with-s3)).

The custom-domains route has no hostname, so it answers every hostname that
reaches it and no other route claims (see the warning under
[Ingress](#ingress)).

With the Gateway API, `httpRoute.customDomains.parentRefs` defaults to
`httpRoute.parentRefs`; a parent reference without `sectionName` attaches it
to every listener of that Gateway. A listener with a fixed hostname (like
`https-appwrite` above) never matches a custom domain, so attach the route to
listeners of its own without a hostname: one for HTTPS, and a plain HTTP
listener on port 80 for the HTTP-01 challenge. If other applications share
the Gateway, these listeners take every hostname their routes don't claim.

```yaml
# Gateway listeners
    - name: http-custom-domains
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces: {from: All}
    - name: https-custom-domains
      port: 443
      protocol: HTTPS
      tls:
        certificateRefs: [{name: custom-domains-tls}]
      allowedRoutes:
        namespaces: {from: All}
```

```yaml
# values.yaml
httpRoute:
  customDomains:
    enabled: true
    parentRefs:
      - {name: public, namespace: gateway, sectionName: http-custom-domains}
      - {name: public, namespace: gateway, sectionName: https-custom-domains}
```

Step 1 also needs DNS: Appwrite resolves the domain through `_APP_DNS`
(default `8.8.8.8`), and the hosts of migration sources and avatar URLs
through `_APP_DNS_EXTERNAL` (by default the same). With
`networkPolicy.egress.enabled`, allow that resolver on port 53 in
`networkPolicy.egress.extraRules`, or point both at a resolver the policy
already allows (through `appwrite.config`):

```yaml
networkPolicy:
  egress:
    extraRules:
      - to: [{ipBlock: {cidr: 8.8.8.8/32}}]
        ports: [{port: 53, protocol: UDP}, {port: 53, protocol: TCP}]
```

Step 3 produces files your ingress controller doesn't read. Pick one:

- **Manage custom-domain TLS outside Appwrite.** For each custom domain, add
  an Ingress (or Gateway listener) with a cert-manager certificate that routes
  to the API Service. Simplest when custom domains are rare.
- **Serve Appwrite's certificates with Traefik.** Run Traefik with its file
  provider reading `/storage/config` and `/storage/certificates` from the same
  volume (ReadWriteMany), as the Docker install does.

## NetworkPolicies and DNS

Every policy that limits egress allows DNS on port 53, UDP and TCP, to the
peers in `networkPolicy.egress.dns` (by default pods labelled
`k8s-app: kube-dns` in any namespace):

| Policy | Pods | Created when |
| --- | --- | --- |
| `<fullname>-egress` | the release, except the browser | `networkPolicy.enabled` and `networkPolicy.egress.enabled` |
| `<fullname>-browser-egress` | the browser | `networkPolicy.enabled` and `browser.enabled` |
| `<fullname>-build` | build pods | `compute.enabled`, even without `networkPolicy.enabled` (turn off with `compute.builds.networkPolicy.enabled`) |
| `<fullname>-executor` | the executor and its runtimes | `compute.enabled`, even without `networkPolicy.enabled` (turn off with `compute.executor.networkPolicy.enabled`) |

Check this before you enable Functions and Sites: on clusters that serve DNS
somewhere else, builds and executions can't resolve names until you adjust
it ([executor.md](executor.md#cluster-dns)).

**NodeLocal DNSCache** answers on a link-local address (usually
`169.254.20.10`), which a pod selector doesn't match, and the build, executor
and browser policies block link-local addresses. Add the address to
`networkPolicy.egress.dns`, which every policy above uses:

```yaml
networkPolicy:
  egress:
    dns:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      - ipBlock:
          cidr: 169.254.20.10/32
```

**OpenShift** DNS pods listen on port 5353, and the port in these policies is
fixed at 53. Add a rule for each policy that exists in your installation:

```yaml
networkPolicy:
  egress:
    extraRules: &openshift-dns
      - to:
          - namespaceSelector:
              matchLabels:
                kubernetes.io/metadata.name: openshift-dns
        ports:
          - {port: 5353, protocol: UDP}
          - {port: 5353, protocol: TCP}
compute:
  builds:
    networkPolicy:
      extraEgress: *openshift-dns
  executor:
    networkPolicy:
      extraEgress: *openshift-dns
```

The browser's policy takes no extra rules, so on OpenShift the browser can't
resolve names while `networkPolicy.enabled` is on.

See [security.md](security.md#network-policies) for what each policy allows.

## Upload limits and timeouts

- Appwrite accepts files up to `_APP_STORAGE_LIMIT` (30 MB by default). The
  SDKs upload larger files in 5 MB chunks, so each request carries at most
  about 5 MB. Set your controller's request body limit above that (some
  default to 1 MB), or to the full storage limit for clients that upload in
  one request.
- Realtime connections are long-lived WebSockets. Make sure idle timeouts on
  the controller and any cloud load balancer in front of it are at least a few
  minutes; clients reconnect automatically when they're closed.
- Synchronous function executions wait up to 30 seconds through the API and
  up to 60 seconds on function and site domains; use asynchronous executions
  for longer runs. Keep the controller's request timeout above 60 seconds.
  With Gateway API, `httpRoute.timeouts` sets it on every rule except
  realtime, whose WebSockets a request timeout would cut:

  ```yaml
  httpRoute:
    timeouts:
      request: 90s
  ```

## Testing routes

`hack/routes.sh`, in this repository, checks every route through a
controller, as CI does with Traefik. It port-forwards to the controller's
Service on port 80 and sends plain HTTP requests, so it expects
`appwrite.forceHttps: false`, the default preview domains and the
custom-domains route:

```console
hack/routes.sh appwrite.example.com <controller-namespace> <controller-service>
```

Add `--header-match` as a fourth argument to also check
`httpRoute.hostnameHeaderMatch`.
