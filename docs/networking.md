# Networking, TLS and domains

Appwrite's Docker install puts Traefik in front of everything. On Kubernetes
the chart creates the same routes for your ingress controller or Gateway.

## Routes

| Hostname | Path | Goes to |
| --- | --- | --- |
| `appwrite.domain` (and `appwrite.consoleDomain`) | `/v1/realtime` | realtime (WebSocket) |
| | `/v1`, `/.well-known` | API |
| | everything else | console |
| `*.functions.<domain>`, `*.sites.<domain>` | everything | API (function and site previews) |
| any other hostname | everything | API (custom domains), optional |

Every route goes to a ClusterIP Service on port 80. Pick one of the two
mechanisms below.

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
| `<fullname>-wildcard` | `*.functions.<domain>`, `*.sites.<domain>` | `ingress.wildcard.tls.secretName` (default `<fullname>-wildcard-tls`) |
| `<fullname>-custom-domains` | a rule without a host | none |

The chart adds no controller-specific annotations. Add what your controller
needs through `ingress.annotations` (all three), `ingress.wildcard.annotations`
or `ingress.customDomains.annotations`.

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
(default `x-forwarded-for`). Make sure your controller sets it, and that
clients can't spoof it.

### cert-manager

- **Main domain:** HTTP-01 works. Annotate the main Ingress (or the Gateway)
  with your issuer, for example
  `cert-manager.io/cluster-issuer: letsencrypt`.
- **Preview wildcards** (`*.functions.<domain>`, `*.sites.<domain>`): wildcard
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
2. asks Let's Encrypt for a certificate with an HTTP-01 challenge that the API
   answers from `/storage/certificates`;
3. stores the certificate in `/storage/certificates/<domain>` and writes a
   Traefik configuration file to `/storage/config`.

On Kubernetes, steps 1 and 2 work when HTTP traffic for unknown hostnames
reaches the API: enable `ingress.customDomains` or `httpRoute.customDomains`
and make sure port 80 isn't redirected before the request reaches Appwrite.

With the Gateway API, `httpRoute.customDomains.parentRefs` defaults to
`httpRoute.parentRefs`. A listener with a fixed hostname (like
`https-appwrite` above) never matches a custom domain, so attach the route to
a listener without a hostname, plus a plain HTTP listener on port 80 for the
HTTP-01 challenge:

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
(default `8.8.8.8`). With `networkPolicy.egress.enabled`, allow that resolver
on port 53 in `networkPolicy.egress.extraRules`, or point `_APP_DNS` at a
resolver the policy already allows (through `appwrite.config`).

Step 3 produces files your ingress controller doesn't read. Pick one:

- **Manage custom-domain TLS outside Appwrite.** For each custom domain, add
  an Ingress (or Gateway listener) with a cert-manager certificate that routes
  to the API Service. Simplest when custom domains are rare.
- **Serve Appwrite's certificates with Traefik.** Run Traefik with its file
  provider reading `/storage/config` and `/storage/certificates` from the same
  volume (ReadWriteMany), as the Docker install does.

## NetworkPolicies and DNS

The policies that restrict egress (`<fullname>-egress` with
`networkPolicy.egress.enabled`, the browser's, and the build namespace's)
allow DNS on port 53, UDP and TCP, to the peers in `networkPolicy.egress.dns`
(by default pods labelled `k8s-app: kube-dns`). The port is fixed. Clusters
that serve DNS elsewhere need an extra rule, in `networkPolicy.egress.extraRules`
for the release and in `compute.builds.networkPolicy.extraEgress` for build
pods:

- **OpenShift** DNS pods listen on 5353. Allow port 5353 to the
  `openshift-dns` namespace.
- **NodeLocal DNSCache** answers on a link-local address (usually
  `169.254.20.10`), which a pod selector doesn't match. Allow that address as
  an `ipBlock` on port 53.

See [security.md](security.md#network-policies) for what each policy allows.

## Upload limits and timeouts

- Appwrite accepts files up to `_APP_STORAGE_LIMIT` (30 MB by default), and
  the SDKs upload in 5 MB chunks. Raise your controller's request body limit
  if it's lower.
- Realtime connections are long-lived WebSockets. Make sure idle timeouts on
  the controller and any cloud load balancer in front of it are at least a few
  minutes; clients reconnect automatically when they're closed.
- Synchronous function executions can run up to `_APP_FUNCTIONS_TIMEOUT`
  (900 seconds by default). Raise request timeouts for the API if you rely on
  long synchronous executions.

## Testing routes

`hack/routes.sh` checks every route through a controller, as CI does with
Traefik:

```console
hack/routes.sh appwrite.example.com <controller-namespace> <controller-service>
```
