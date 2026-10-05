# Optional components

Appwrite's Docker install ships a few supporting services. The chart can run
each of them; they're off by default except geo.

| Component | Value | Default | What breaks without it |
| --- | --- | --- | --- |
| Geo | `geo.enabled` | on | Sessions and logs have no country or location. |
| Browser | `browser.enabled` | off | Site screenshots and `/v1/avatars/screenshots`. |
| Assistant | `assistant.enabled` | off | The console's AI assistant. |
| Autogravity | `autogravity.enabled` | off | Focal-point detection for image previews (`gravity=auto`). |
| Embedding | `embedding.enabled` | off | Embedding features of VectorsDB. |
| MQTT | `mqtt.enabled` | off | Realtime over MQTT; WebSocket realtime is unaffected. |

## Browser

```yaml
browser:
  enabled: true
```

A headless Chromium (Playwright) that renders screenshots of sites and of
arbitrary URLs through the avatars API. Because users choose those URLs,
with `networkPolicy.enabled` the browser may only reach DNS, the Appwrite
API and public IP addresses: private, link-local and CGNAT ranges are blocked,
so it can't be used to probe the cluster. With `networkPolicy.egress.enabled`
as well, the release-wide egress policy also lets it reach the release's
other pods ([security.md](security.md#network-policies)). It runs as UID 999 with a memory
`emptyDir` for `/dev/shm`.

## Assistant

```yaml
assistant:
  enabled: true
  existingSecret: openai       # key: openai-api-key
```

Appwrite reaches the assistant at the fixed address
`http://appwrite-assistant:3003`, so its Service is named
`appwrite-assistant` regardless of the release name. Only one release per
namespace can enable it. The key is also passed to Appwrite, which is how the
console knows to show the assistant.

## Autogravity

```yaml
autogravity:
  enabled: true
```

Detects the subject of an image so previews with `gravity=auto` crop around
it. CPU-heavy; size `autogravity.resources` for your preview traffic.

## Embedding

```yaml
embedding:
  enabled: true
  models: [nomic-embed-text]
  persistence:
    size: 5Gi
```

Downloads its models on first start (about 600 MB of memory per model
instance) and keeps them on a PersistentVolumeClaim. It runs as a single pod
that is recreated, not rolled, on updates. Without it the chart sets
`_APP_EMBEDDING=disabled`.

## MQTT

```yaml
mqtt:
  enabled: true
  service:
    type: LoadBalancer
    loadBalancerSourceRanges: [203.0.113.0/24]
```

Appwrite's MQTT broker serves plain MQTT on 1883 and MQTT over WebSocket on
8083. In the Docker install, Traefik terminates TLS on 8883 and 8084; on
Kubernetes, terminate TLS on the load balancer (most clouds support a TLS
listener through Service annotations) or put a TCP proxy in front.

The broker ignores Redis ACL users, so with an external Redis use the
`default` user (`externalRedis.username` empty).
