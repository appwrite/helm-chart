# Optional components

Appwrite's Docker install ships a few supporting services. The chart can run
each of them. Geo, the browser and ExifTool are on by default; the others are
off until you enable them.

| Component | Value | Default | What it gives you |
| --- | --- | --- | --- |
| [Geo](#geo) | `geo.enabled` | on | Country and location for sessions and logs. |
| [Browser](#browser) | `browser.enabled` | on | Site screenshots and `/v1/avatars/screenshots`. |
| [ExifTool](#exiftool) | `exiftool.enabled` | on | Location, camera and capture time removed from images in buckets that ask for it. |
| [Autogravity](#autogravity) | `autogravity.enabled` | off | Image previews cropped around the subject (`gravity=auto`). |
| [Embedding](#embedding) | `embedding.enabled` | off | The embeddings API, which turns text into vectors. |
| [MQTT](#mqtt) | `mqtt.enabled` | off | Push notifications over MQTT, through Messaging's Appwrite provider. |

The chart connects each one to Appwrite when you enable it; you don't set
any `_APP_*` variables yourself. Each has its own `resources`,
`nodeSelector`, `tolerations`, `affinity` and `priorityClassName`.
[Resources and images](#resources-and-images) lists the defaults.

## Geo

Appwrite looks up the country and location of the IP addresses behind
sessions and logs through the geo service. Turn it off to save a pod:

```yaml
geo:
  enabled: false
```

Appwrite then skips geolocation. The geo server listens on port 80, so its
pod lowers `net.ipv4.ip_unprivileged_port_start` instead of running as root.

## Browser

A headless Chromium that renders screenshots: of each site deployment, shown
in the console, and of any URL through the avatars API. It's on by default,
because Sites are. To turn it off:

```yaml
browser:
  enabled: false
```

Without it, every site deployment logs "Screenshot capturing failed" and the
console shows no preview; the site itself deploys and serves normally.

Users choose the URLs it loads, so treat it as a way into your network. With
`networkPolicy.enabled`, the `<fullname>-browser-egress` policy limits it to
DNS, the Appwrite API and public IPv4 addresses. Private, loopback,
link-local (including cloud metadata addresses), CGNAT and other reserved
ranges are blocked, so it can't be used to probe the cluster. The
release-wide egress policy (`networkPolicy.egress.enabled`) doesn't apply to
the browser, so these limits hold either way. Without `networkPolicy.enabled`
nothing restricts it. See [security.md](security.md#network-policies).

It runs as UID 999 with a read-only root filesystem, a writable `/tmp`, and
a 256 MiB in-memory `/dev/shm` for Chromium, which counts towards its memory
limit. Scale it with `browser.replicaCount`.

## ExifTool

Appwrite 2.6 can remove location, device and capture-time metadata from
images as they're uploaded: turn on *Image metadata* in a bucket's settings
(`stripMetadata` in the API). Color profiles and orientation are kept, and
pixels aren't re-encoded. The work is done by an
[ExifTool](https://github.com/appwrite/exiftool) service, which the chart
runs by default. To turn it off:

```yaml
exiftool:
  enabled: false
```

Without it, buckets with the setting on store images as uploaded, metadata
and all, and only a warning in the API's log says so. The same happens when
ExifTool fails or can't be reached, for images over 20 MB, and for uploads
through the S3-compatible API. Existing files are never rewritten. If you
rely on the setting to keep locations private, watch the
`<fullname>-exiftool` pod.

Only the API calls it, and only for new uploads to such buckets. Each pod
runs `exiftool.concurrency` (2) ExifTool processes of about 50 MiB, and
strips that many images at once. Raise it, or `exiftool.replicaCount`, for
buckets that take many photos at once. It runs as UID 65532 with a read-only
root filesystem; uploads are written to an `emptyDir` at `/tmp` while they're
stripped.

## Autogravity

Finds the subject of an image, so that previews requested with
`gravity=auto` crop around it. Without it, those requests fail with an
error; other gravity values work either way.

```yaml
autogravity:
  enabled: true
```

It runs an image model on the CPU, in a single pod. Appwrite caches the
result for each image, so repeat previews don't analyse it again; size
`autogravity.resources` for the rate of new images. `autogravity.modelBackend`
(`MODEL_BACKEND`) picks the model, `focalnet` by default as in the Docker
install.

## Embedding

Serves Appwrite's embeddings API (`/v1/embeddings`), which turns text into
vectors, for example to store in a VectorsDB database. Without it, the chart
sets `_APP_EMBEDDING=disabled` and the API answers that the service is
disabled.

```yaml
embedding:
  enabled: true
  models: [nomic-embed-text]   # the API also accepts all-minilm
  persistence:
    size: 5Gi
```

Load every model your apps ask for. On first start the pod downloads its
models (about 550 MB for `nomic-embed-text`) and keeps them on a
PersistentVolumeClaim, so it needs outbound internet access. With
`networkPolicy.egress.enabled`, add a rule for it to
`networkPolicy.egress.extraRules`. With `embedding.persistence.enabled:
false` the models are downloaded again on every restart.

Models are held in memory: plan for a few GiB, and raise
`embedding.resources` (1Gi requested, 4Gi limit by default) when you load
more than one. It runs as a single pod that is recreated, not rolled, on
updates, and its startup probe allows 15 minutes for the download.

## MQTT

Appwrite's MQTT broker. It delivers push notifications sent through
Messaging's built-in *Appwrite* push provider to the devices and browsers
that subscribe to it, without FCM or APNs. It isn't involved in realtime,
which stays on WebSocket.

```yaml
mqtt:
  enabled: true
  service:
    type: LoadBalancer
    loadBalancerSourceRanges: [203.0.113.0/24]
```

Then add an *Appwrite* push provider to the project's Messaging providers.

The broker serves plain MQTT on 1883 and MQTT over WebSocket on 8083.
Clients send their credentials when they connect, so only expose it with
TLS. The chart's ingress and HTTPRoute don't route MQTT. Terminate TLS on the
load balancer (most clouds support a TLS listener through
`mqtt.service.annotations`) or on a TCP proxy in front of the Service. The
Docker install serves MQTT over TLS on 8883 and MQTT over secure WebSocket
on 8084. To offer the same ports, set `mqtt.service.port: 8883` and
`mqtt.service.wsPort: 8084` and terminate TLS on the load balancer.

With `networkPolicy.enabled`, the `<fullname>-mqtt` policy admits the same
sources as the API (`networkPolicy.ingress.from`, any source when empty). If
you limited those to your ingress controller, clients coming through the
load balancer are blocked too; add their sources to the list.

The broker runs the Appwrite image and connects to the database and Redis
like the API. It ignores Redis ACL users, so the chart refuses
`redis.username` with MQTT enabled; use the `default` user. Scale it
with `mqtt.replicaCount`. `_APP_MQTT_REPLAY_DEPTH` (5) and
`_APP_MQTT_MAX_PACKET_SIZE` (64000) can be changed through `appwrite.config`.

## Resources and images

| Component | Image | Requests | Memory limit | Replicas |
| --- | --- | --- | --- | --- |
| Geo | `docker.io/appwrite/geo:0.3.2` | 20m CPU, 128Mi | 512Mi | `geo.replicaCount` (1) |
| Browser | `docker.io/appwrite/browser:0.3.8` | 100m CPU, 512Mi | 2Gi | `browser.replicaCount` (1) |
| ExifTool | `ghcr.io/appwrite/exiftool:0.1.1` | 20m CPU, 128Mi | 512Mi | `exiftool.replicaCount` (1) |
| Autogravity | `ghcr.io/appwrite/autogravity:0.0.11` | 100m CPU, 512Mi | 2Gi | 1 |
| Embedding | `docker.io/appwrite/embedding:0.3.1` | 250m CPU, 1Gi | 4Gi | 1 |
| MQTT | the Appwrite image | 50m CPU, 128Mi | 512Mi | `mqtt.replicaCount` (1) |

Change the requests and limits under `<component>.resources`, and the image
under `<component>.image`, except MQTT, which follows `image`.
