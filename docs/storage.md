# Storage

Appwrite stores files (bucket uploads, deployment code, build output,
certificates) either on a filesystem under `/storage` or in S3-compatible
object storage.

## Local storage (default)

```yaml
appwrite:
  storage:
    device: local
persistence:
  enabled: true
  size: 20Gi
  accessModes: [ReadWriteOnce]
  storageClass: ""
```

The chart creates one PersistentVolumeClaim, `<fullname>-storage`, and mounts
these paths from it in the API and in the workers that need files:

| Path | Contents |
| --- | --- |
| `/storage/uploads` | bucket files |
| `/storage/functions`, `/storage/sites` | uploaded deployment code |
| `/storage/builds` | build output |
| `/storage/imports` | migration imports |
| `/storage/certificates`, `/storage/config` | Let's Encrypt certificates and ACME challenges |

`/storage/cache` (image previews and other cached responses) is an `emptyDir`
per pod.

### ReadWriteOnce vs ReadWriteMany

Several pods use the volume at once.

- **ReadWriteOnce** (default): every pod that mounts the volume is scheduled
  on the same node, through required pod affinity
  (`persistence.colocateReadWriteOnce`). It works on any cluster, but those pods
  can't spread across nodes, and the node is a single point of failure.
  Draining that node takes them all down at once: a replacement pod can only
  start next to the others, on the node being drained. A PodDisruptionBudget
  would block the drain forever, so the chart doesn't create one for the API
  while it's co-located.
- **ReadWriteMany** (`accessModes: [ReadWriteMany]`): pods spread freely. Use
  a storage class that supports it, such as EFS, Azure Files, Filestore, CephFS,
  Longhorn RWX or NFS. The volume must honour `fsGroup` (82), or be writable
  by UID 82; NFS exports with `root_squash` and no `fsGroup` support need the
  directory owned by 82.

### Existing claims

```yaml
persistence:
  existingClaim: appwrite-files
  accessModes: [ReadWriteMany]    # describes the claim, used for scheduling
```

The created claim is kept on `helm uninstall` (`persistence.keep`); delete it
yourself once you no longer need the data.

## S3

Object storage takes files off the volume, lets pods share them without a
ReadWriteMany claim, and is required for [Functions and Sites](executor.md).

**1. Create a bucket** and an access key that can read, write, list and
delete objects in it. Appwrite doesn't create the bucket.

**2. Store the key in a Secret:**

```console
kubectl -n appwrite create secret generic appwrite-s3 \
  --from-literal=s3-access-key='<access key ID>' \
  --from-literal=s3-secret-key='<secret access key>'
```

**3. Point the chart at it:**

```yaml
appwrite:
  storage:
    device: s3
    s3:
      endpoint: https://fsn1.your-objectstorage.com   # empty for AWS S3
      region: fsn1
      bucket: appwrite
      existingSecret: appwrite-s3                     # or accessKey / secretKey inline
      accessKeyKey: s3-access-key
      secretKeyKey: s3-secret-key
```

With `endpoint` empty, Appwrite talks to AWS S3 with virtual-hosted URLs
(`<bucket>.s3.<region>.amazonaws.com`). With an endpoint, it uses path-style
URLs (`<endpoint>/<bucket>/...`), which every S3-compatible store accepts.

| Provider | `endpoint` | `region` |
| --- | --- | --- |
| AWS S3 | *(empty)* | the bucket's region, e.g. `eu-central-1` |
| Cloudflare R2 | `https://<account id>.r2.cloudflarestorage.com` | `auto` |
| Google Cloud Storage | `https://storage.googleapis.com`, with an [HMAC key](https://cloud.google.com/storage/docs/authentication/hmackeys) | `auto` |
| DigitalOcean Spaces | `https://<region>.digitaloceanspaces.com` | e.g. `fra1` |
| Hetzner Object Storage | `https://<location>.your-objectstorage.com` | e.g. `fsn1` |
| Backblaze B2 | `https://s3.<region>.backblazeb2.com` | e.g. `eu-central-003` |
| Wasabi | `https://s3.<region>.wasabisys.com` | e.g. `eu-central-1` |
| MinIO, SeaweedFS, Garage, Ceph RGW | the S3 API's URL, e.g. `http://minio.minio.svc:9000` | whatever the server expects, often `us-east-1` |

CI tests with SeaweedFS. The other rows come from each provider's
documentation.

Things to know:

- **Static keys only.** Appwrite signs requests with the access key in the
  Secret. IAM roles for service accounts (IRSA, EKS Pod Identity, GKE Workload
  Identity) aren't supported.
- **Everything goes in one bucket**, under one prefix per kind of file. Keep
  the bucket private: Appwrite serves files itself and checks permissions on
  every download.
- **Lifecycle rules.** Don't expire objects; Appwrite deletes what it no
  longer needs. A rule that aborts incomplete multipart uploads after a few
  days is fine.
- **Choose before going live.** Changing `device` later doesn't move files
  that are already stored; they stay where they were written.

### The volume with S3

`/storage` is still used for certificates, ACME challenges and some scratch
files, so the API and the storage workers mount the volume with S3 too. Keep
`persistence.enabled` (a small volume is enough). S3 alone doesn't let those
pods spread across nodes: with a ReadWriteOnce claim they're still
co-located. To scale them across nodes, use a small ReadWriteMany volume:

```yaml
persistence:
  size: 5Gi
  accessModes: [ReadWriteMany]
  storageClass: efs              # any class that supports ReadWriteMany
```

With `persistence.enabled: false` every pod gets its own `emptyDir` at
`/storage`. That works only with a single API pod and the `combined` worker,
and certificates for custom domains are lost on every restart.

## Datastore volumes

The built-in PostgreSQL, Redis and ClickHouse each keep their data on a claim
created from their StatefulSet's `volumeClaimTemplates`, named
`data-<fullname>-<datastore>-0` (for example `data-appwrite-postgresql-0`).
Kubernetes doesn't allow changing a StatefulSet's claim templates, so changing
`<datastore>.persistence.size` after installing makes `helm upgrade` fail.

To grow a volume, with a StorageClass that has `allowVolumeExpansion: true`:

```console
kubectl -n appwrite patch pvc data-appwrite-postgresql-0 \
  -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'
kubectl -n appwrite delete statefulset appwrite-postgresql --cascade=orphan
helm upgrade appwrite <chart> -n appwrite --reuse-values --set postgresql.persistence.size=50Gi
```

Deleting the StatefulSet with `--cascade=orphan` leaves the pod and the claim
alone. The upgrade recreates the StatefulSet with the new size, and the pod
carries on.

## Antivirus

Appwrite can scan uploads with ClamAV:

```yaml
appwrite:
  config:
    _APP_STORAGE_ANTIVIRUS: enabled
    _APP_STORAGE_ANTIVIRUS_HOST: clamav.clamav.svc.cluster.local
    _APP_STORAGE_ANTIVIRUS_PORT: "3310"
```

Run ClamAV separately (for example with its official image as a Deployment).
