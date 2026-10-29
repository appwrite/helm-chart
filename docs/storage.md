# Storage

Appwrite stores files (bucket uploads, deployment code, build output,
certificates) either on a volume under `/storage` or in S3-compatible object
storage. `storage.device` picks one:

| | `s3` (default) | `local` |
| --- | --- | --- |
| Files live on | a bucket: the [built-in object storage](#built-in-object-storage) or [your own](#your-own-s3-store) | a PersistentVolumeClaim |
| Spreading the API and workers across nodes | still needs a small ReadWriteMany volume ([why](#the-volume-with-s3)) | needs a ReadWriteMany volume |
| [Functions and Sites](executor.md) | required | not supported: set `compute.enabled: false` |
| [Antivirus](#antivirus) scanning | not supported | supported |

Choose before going live: changing `device` later doesn't move files that are
already stored. They stay where they were written.

## Local storage

Files on the `/storage` volume, without Functions and Sites:

```yaml
compute:
  enabled: false
storage:
  device: local
  volume:
    enabled: true
    size: 20Gi
    accessModes: [ReadWriteOnce]
    storageClass: ""          # empty: global.storageClass, then the cluster default
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

The claim is kept on `helm uninstall` (`storage.volume.keep`, on by default), so
your files survive a reinstall. Delete it yourself once you no longer need
the data:

```console
kubectl -n appwrite delete pvc appwrite-storage
```

### ReadWriteOnce vs ReadWriteMany

Several pods use the volume at once.

- **ReadWriteOnce** (default): every pod that mounts the volume is scheduled
  on the same node, through required pod affinity
  (`storage.volume.colocateReadWriteOnce`). It works on any cluster, but those pods
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

To use a claim you created yourself, name it and describe its access mode:

```yaml
storage:
  volume:
    existingClaim: appwrite-files
    accessModes: [ReadWriteMany]  # the claim's access mode, used for scheduling
```

The chart then creates no claim of its own, and ignores `size` and
`storageClass`.

## S3

Object storage takes files off the volume, lets pods share them without a
ReadWriteMany claim, and is required for [Functions and Sites](executor.md).
`storage.s3.mode` picks where the bucket lives: in the release (`builtin`,
the default), or in a store you run or buy (`external`).

### Built-in object storage

```yaml
storage:
  device: s3
```

That's all. The chart runs [SeaweedFS](https://github.com/seaweedfs/seaweedfs),
an Apache-2.0 S3-compatible store, as a single-replica StatefulSet
(`<fullname>-seaweedfs`) on a 20Gi volume
(`storage.s3.builtin.persistence.size`). It creates the bucket
(`storage.s3.bucket`, `appwrite` by default) when it starts, and the chart
generates its access keys once and keeps them in its Secret (`s3-access-key`,
`s3-secret-key`), like the other built-in credentials. Appwrite, the
orchestrator, build Jobs and the executor reach it at
`http://<fullname>-seaweedfs.<namespace>.svc:8333`; it has no route from
outside the cluster. With `networkPolicy.enabled`, the
`<fullname>-object-storage` policy lets only those pods in.

It's one pod and one volume, without replication: back the volume up
([backup-restore.md](backup-restore.md)), or use your own store with
redundancy once real users depend on the install. The volume grows like the
[datastore volumes](#datastore-volumes) (claim `data-<fullname>-seaweedfs-0`).
SeaweedFS fills it with volume files of `storage.s3.builtin.volumeSizeLimitMB`
(1024 MB), so keep the claim at a few GB at least.

### Your own S3 store

```yaml
storage:
  device: s3
  s3:
    mode: external
```

**1. Create a bucket** and an access key that can read, write, list and
delete objects in it. Appwrite doesn't create the bucket. On AWS, an IAM
user with this policy is enough:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::appwrite-example-com"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"],
      "Resource": "arn:aws:s3:::appwrite-example-com/*"
    }
  ]
}
```

**2. Store the key in a Secret:**

```console
kubectl -n appwrite create secret generic appwrite-s3 \
  --from-literal=s3-access-key='<access key ID>' \
  --from-literal=s3-secret-key='<secret access key>'
```

**3. Point the chart at it:**

```yaml
storage:
  device: s3
  s3:
    mode: external
    external:
      endpoint: https://fsn1.your-objectstorage.com   # empty for AWS S3
      region: fsn1                                    # default us-east-1
    bucket: appwrite
    accessKeyId:
      secretName: appwrite-s3                       # or value: ... inline
      secretKey: s3-access-key                      # the default
    secretAccessKey:
      secretName: appwrite-s3
      secretKey: s3-secret-key                      # the default
```

The chart refuses to install without `bucket`, or without a `value` or a
`secretName` for both `accessKeyId` and `secretAccessKey`
([credentials](external-databases.md#credentials)). With
[Functions and Sites](executor.md) and a `secretName`, the executor needs a
copy of the keys in its own namespace
([executor.md](executor.md#existing-secrets),
[`examples/functions-existing-secrets.yaml`](../examples/functions-existing-secrets.yaml)).
If you restricted egress with
`networkPolicy.egress.enabled`, allow the endpoint in
`networkPolicy.egress.extraRules` ([security.md](security.md#egress)).

With `storage.s3.external.endpoint` empty, Appwrite talks to AWS S3 with virtual-hosted URLs
(`<bucket>.s3.<region>.amazonaws.com`). With an endpoint, it uses path-style
URLs (`<endpoint>/<bucket>/...`), which every S3-compatible store accepts,
unless the endpoint already names the bucket: its host is the bucket or
starts with `<bucket>.`, or its path ends with it. A custom domain pointing
at the bucket can't be told apart from a bare service; set
`storage.s3.external.pathStyle: disabled` for one, or `enabled` to always
name the bucket in the path (`_APP_STORAGE_S3_PATH_STYLE`, Appwrite 2.6 and
later). The built-in store always uses path-style URLs. An endpoint without
a scheme gets `https://`.

| Provider | `external.endpoint` | `external.region` |
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
  days is fine: Appwrite uploads large files in parts.
- **No antivirus.** Appwrite only scans files stored on the volume.

### The volume with S3

`/storage` is still used for certificates, ACME challenges and some scratch
files, so the API and the storage workers mount the volume with S3 too. Keep
`storage.volume.enabled` (a small volume is enough). S3 alone doesn't let those
pods spread across nodes: with a ReadWriteOnce claim they're still
co-located. To scale them across nodes, use a small ReadWriteMany volume:

```yaml
storage:
  volume:
    size: 5Gi
    accessModes: [ReadWriteMany]
    storageClass: efs            # any class that supports ReadWriteMany
```

With `storage.volume.enabled: false` every pod gets its own `emptyDir` at
`/storage`. That works only with a single API pod and the `combined` worker,
and certificates for custom domains are lost on every restart.

## File size limits

| Value | Default | Sets |
| --- | --- | --- |
| `storage.limit` | `30000000` (30 MB) | the largest file Appwrite accepts (`_APP_STORAGE_LIMIT`) |
| `storage.previewLimit` | `20000000` (20 MB) | the largest file Appwrite renders previews for (`_APP_STORAGE_PREVIEW_LIMIT`) |

Your ingress controller's request body limit matters too
([networking.md](networking.md#upload-limits-and-timeouts)).

## Datastore volumes

The built-in PostgreSQL, Redis, ClickHouse and SeaweedFS each keep their data on a claim
created from their StatefulSet's `volumeClaimTemplates`, named
`data-<fullname>-<datastore>-0` (for example `data-appwrite-postgresql-0`).
Kubernetes doesn't allow changing a StatefulSet's claim templates, so changing
`<service>.builtin.persistence.size` (`database`, `redis` or `clickhouse`,
and `storage.s3.builtin.persistence.size`) after installing makes
`helm upgrade` fail.

To grow a volume, with a StorageClass that has `allowVolumeExpansion: true`:

1. Resize the claim, and delete the StatefulSet without its pod:

   ```console
   kubectl -n appwrite patch pvc data-appwrite-postgresql-0 \
     -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'
   kubectl -n appwrite delete statefulset appwrite-postgresql --cascade=orphan
   ```

2. Set the same size in your values
   (`database.builtin.persistence.size: 50Gi`) and upgrade:

   ```console
   helm upgrade appwrite oci://ghcr.io/appwrite/charts/appwrite \
     --version <chart version> -n appwrite -f values.yaml
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
Appwrite 2.6.2 scans only:

- with `device: local`. Files stored in S3 aren't scanned.
- files up to 20 MB.
- in buckets whose antivirus setting is on (the default for new buckets).
