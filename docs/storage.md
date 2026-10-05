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

With S3, uploads, deployment code and build output live in the bucket, which
is what lets the API and workers scale across nodes without a ReadWriteMany
volume, and what builds and the executor need
([executor.md](executor.md)). Create the bucket before installing; Appwrite
doesn't create it.

`/storage` is still used for certificates, ACME challenges and some scratch
files, so keep `persistence.enabled` (a small volume is enough) unless
you manage TLS for custom domains outside Appwrite.

Tested with SeaweedFS; any S3-compatible store that supports path-style
requests should work (Ceph RGW, Garage, Hetzner, Cloudflare R2, AWS S3, ...).

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
