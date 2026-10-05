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

```yaml
appwrite:
  storage:
    device: s3
    s3:
      endpoint: https://fsn1.your-objectstorage.com   # empty for AWS S3
      region: eu-central
      bucket: appwrite
      existingSecret: appwrite-s3                     # or accessKey / secretKey
      accessKeyKey: s3-access-key
      secretKeyKey: s3-secret-key
```

With S3, uploads, deployment code and build output live in the bucket. Builds
and the executor need that ([executor.md](executor.md)). Create the bucket
before installing; Appwrite doesn't create it.

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

Tested with SeaweedFS; any S3-compatible store that supports path-style
requests should work (Ceph RGW, Garage, Hetzner, Cloudflare R2, AWS S3, ...).

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
