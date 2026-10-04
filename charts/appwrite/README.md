# Appwrite Helm chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2.3.0](https://img.shields.io/badge/AppVersion-2.3.0-informational?style=flat-square)

Appwrite, the open-source backend platform, on Kubernetes. Deploys the API, console, realtime, workers and schedulers with optional built-in PostgreSQL, Redis and ClickHouse.

> [!WARNING]
> This chart is under active development and not yet released. Values and
> behaviour may change between pre-1.0 versions.

## Requirements

- Kubernetes >=1.29.0-0
- Helm 4.x, or Helm 3.18+

## Installing

```console
helm install appwrite oci://ghcr.io/levivannoort/charts/appwrite \
  --namespace appwrite --create-namespace
```

## Uninstalling

```console
helm uninstall appwrite --namespace appwrite
```

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| levivannoort |  | <https://github.com/levivannoort> |

## Source Code

* <https://github.com/levivannoort/helm-chart>
* <https://github.com/appwrite/appwrite>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| api.affinity | object | `{}` | Affinity. Empty inherits `defaults.affinity`. |
| api.autoscaling.behavior | object | `{}` | HPA scaling behaviour. |
| api.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| api.autoscaling.maxReplicas | int | `10` | Maximum replicas. |
| api.autoscaling.minReplicas | int | `2` | Minimum replicas. |
| api.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| api.autoscaling.targetMemoryUtilizationPercentage | string | `""` | Target average memory utilisation, in percent. Empty disables the metric. |
| api.containerSecurityContext | object | `{}` | Container security context. Empty inherits `containerSecurityContext`. |
| api.cpuNum | string | `""` | CPUs Appwrite sizes its worker and connection pools for (`_APP_CPU_NUM`). Derived from the CPU limit, then the CPU request, when empty. |
| api.extraContainers | list | `[]` | Extra sidecar containers. |
| api.extraEnv | list | `[]` | Extra environment variables for this component. |
| api.extraInitContainers | list | `[]` | Extra init containers. |
| api.extraVolumeMounts | list | `[]` | Extra volume mounts for the main container. |
| api.extraVolumes | list | `[]` | Extra volumes for this component. |
| api.livenessProbe.enabled | bool | `true` | Enable the liveness probe. |
| api.livenessProbe.failureThreshold | int | `6` |  |
| api.livenessProbe.periodSeconds | int | `10` |  |
| api.livenessProbe.timeoutSeconds | int | `5` |  |
| api.nodeSelector | object | `{}` | Node selector. Empty inherits `defaults.nodeSelector`. |
| api.pdb.enabled | bool | `true` | Create a PodDisruptionBudget when more than one replica can run. |
| api.pdb.maxUnavailable | int | `1` | Maximum unavailable pods. |
| api.pdb.minAvailable | string | `""` | Minimum available pods. Takes precedence over `maxUnavailable`. |
| api.podAnnotations | object | `{}` | Pod annotations, merged over `defaults.podAnnotations`. |
| api.podLabels | object | `{}` | Pod labels, merged over `defaults.podLabels`. |
| api.podSecurityContext | object | `{}` | Pod security context. Empty inherits `podSecurityContext`. |
| api.preStopSleepSeconds | int | `5` | Seconds to sleep before shutdown so endpoints are removed first. |
| api.priorityClassName | string | `""` | Priority class. Empty inherits `defaults.priorityClassName`. |
| api.readinessProbe.enabled | bool | `true` | Enable the readiness probe. |
| api.readinessProbe.failureThreshold | int | `3` |  |
| api.readinessProbe.periodSeconds | int | `10` |  |
| api.readinessProbe.successThreshold | int | `1` |  |
| api.readinessProbe.timeoutSeconds | int | `5` |  |
| api.replicaCount | int | `1` | Number of API replicas. Ignored when autoscaling is enabled. |
| api.resources | object | `{"limits":{"memory":"2Gi"},"requests":{"cpu":"250m","memory":"512Mi"}}` | Resource requests and limits. |
| api.service.annotations | object | `{}` | Service annotations. |
| api.service.port | int | `80` | Service port. |
| api.service.type | string | `"ClusterIP"` | Service type. |
| api.startupProbe.enabled | bool | `true` | Enable the startup probe. The first start creates database schemas and can take minutes. |
| api.startupProbe.failureThreshold | int | `72` |  |
| api.startupProbe.initialDelaySeconds | int | `5` |  |
| api.startupProbe.periodSeconds | int | `5` |  |
| api.startupProbe.timeoutSeconds | int | `5` |  |
| api.terminationGracePeriodSeconds | int | `45` | Seconds to wait for in-flight requests on shutdown. Swoole drains for up to 30s. |
| api.tolerations | list | `[]` | Tolerations. Empty inherits `defaults.tolerations`. |
| api.topologySpreadConstraints | list | `[]` | Topology spread constraints. Empty inherits `defaults.topologySpreadConstraints`. |
| api.updateStrategy | object | `{"rollingUpdate":{"maxSurge":"25%","maxUnavailable":0},"type":"RollingUpdate"}` | Deployment update strategy. |
| appwrite.autoCertificates | bool | `false` | Have Appwrite issue Let's Encrypt certificates for function and site subdomains (`_APP_ROUTER_AUTO_CERTIFICATES`). Off by default: TLS for wildcard domains is expected to terminate at the ingress or Gateway. |
| appwrite.certificatesEmail | string | `""` | Email used to register Let's Encrypt certificates (`_APP_EMAIL_CERTIFICATES`). Required. |
| appwrite.config | object | `{}` | Extra `_APP_*` environment variables for every Appwrite pod. They override the chart's defaults and computed values; see https://appwrite.io/docs/advanced/self-hosting/configuration/environment-variables. |
| appwrite.console.whitelistEmails | list | `[]` | Emails allowed to sign up to the console (`_APP_CONSOLE_WHITELIST_EMAILS`). |
| appwrite.console.whitelistIPs | list | `[]` | IPs allowed to sign up to the console (`_APP_CONSOLE_WHITELIST_IPS`). |
| appwrite.console.whitelistRoot | bool | `true` | Only the first user can sign up to the console; everyone else needs an invite (`_APP_CONSOLE_WHITELIST_ROOT`). |
| appwrite.consoleDomain | string | `""` | Hostname of the console (`_APP_CONSOLE_DOMAIN`). Defaults to `domain`. |
| appwrite.database.connectionsMax | int | `151` | Total connections Appwrite may open to the database, shared by all pods (`_APP_CONNECTIONS_MAX`). Keep it below the database's `max_connections`. |
| appwrite.database.poolClients | int | `15` | Number of Appwrite processes sharing `connectionsMax` (`_APP_POOL_CLIENTS`). Must be at least the number of Appwrite pods. |
| appwrite.domain | string | `""` | Hostname of the Appwrite API and console (`_APP_DOMAIN`). Required. |
| appwrite.domainTargets.a | string | `""` | IPv4 addresses custom domains may point an A record to, comma-separated (`_APP_DOMAIN_TARGET_A`). |
| appwrite.domainTargets.aaaa | string | `""` | IPv6 addresses custom domains may point an AAAA record to, comma-separated (`_APP_DOMAIN_TARGET_AAAA`). |
| appwrite.domainTargets.caa | string | `""` | CAA record value custom domains must allow (`_APP_DOMAIN_TARGET_CAA`). |
| appwrite.domainTargets.cname | string | `""` | Hostname custom domains must CNAME to (`_APP_DOMAIN_TARGET_CNAME`). Defaults to `domain`. |
| appwrite.extraEnv | list | `[]` | Extra environment variables for every Appwrite container, as a list of EnvVar objects. |
| appwrite.extraEnvFrom | list | `[]` | Extra `envFrom` sources for every Appwrite container. |
| appwrite.forceHttps | bool | `true` | Redirect HTTP to HTTPS and generate HTTPS URLs (`_APP_OPTIONS_FORCE_HTTPS` and `_APP_OPTIONS_ROUTER_FORCE_HTTPS`). Turn it off only when TLS isn't terminated in front of Appwrite. |
| appwrite.functionsDomain | string | `""` | Parent domain for function preview URLs (`_APP_DOMAIN_FUNCTIONS`). Defaults to `functions.<domain>`. |
| appwrite.logFormat | string | `"json"` | Log format (`_APP_LOGGING_FORMAT`). |
| appwrite.routerProtection | bool | `false` | Reject requests for hostnames Appwrite doesn't know (`_APP_OPTIONS_ROUTER_PROTECTION`). |
| appwrite.secretConfig | object | `{}` | Extra sensitive `_APP_*` environment variables, stored in a Secret. |
| appwrite.secrets.allowKeyRotation | bool | `false` | Allow `opensslKey` to differ from the key already stored in the cluster. Appwrite can't re-encrypt data, so changing the key makes encrypted data unreadable. |
| appwrite.secrets.existingSecret | string | `""` | Existing Secret holding the core secrets. When empty the chart generates them once and keeps them across upgrades and uninstalls. |
| appwrite.secrets.generate | bool | `true` | Generate missing credentials (core secrets and built-in datastore passwords). Set to false with GitOps tools that render templates without cluster access (Argo CD, `helm template`), where generated values would change on every render. |
| appwrite.secrets.geoSecret | string | `""` | Explicit `_APP_GEO_SECRET`. |
| appwrite.secrets.keys.geoSecret | string | `"_APP_GEO_SECRET"` | Key holding `_APP_GEO_SECRET`, shared with the geo service. |
| appwrite.secrets.keys.opensslKey | string | `"_APP_OPENSSL_KEY_V1"` | Key holding `_APP_OPENSSL_KEY_V1`, which encrypts data at rest and signs JWTs. |
| appwrite.secrets.keys.trackingSecret | string | `"_APP_NOTIFICATIONS_TRACKING_SECRET"` | Key holding `_APP_NOTIFICATIONS_TRACKING_SECRET`. |
| appwrite.secrets.opensslKey | string | `""` | Explicit `_APP_OPENSSL_KEY_V1`, e.g. when migrating from Docker. Never change it after install. |
| appwrite.secrets.trackingSecret | string | `""` | Explicit `_APP_NOTIFICATIONS_TRACKING_SECRET`. |
| appwrite.sitesDomain | string | `""` | Parent domain for site preview URLs (`_APP_DOMAIN_SITES`). Defaults to `sites.<domain>`. |
| appwrite.smtp.existingSecret | string | `""` | Existing Secret holding the SMTP password. |
| appwrite.smtp.host | string | `""` | SMTP server (`_APP_SMTP_HOST`). Empty disables email. |
| appwrite.smtp.password | string | `""` | SMTP password (`_APP_SMTP_PASSWORD`). Ignored when `existingSecret` is set. |
| appwrite.smtp.passwordKey | string | `"smtp-password"` | Key in `existingSecret` holding the SMTP password. |
| appwrite.smtp.port | int | `587` | SMTP port (`_APP_SMTP_PORT`). |
| appwrite.smtp.secure | string | `"tls"` | SMTP encryption (`_APP_SMTP_SECURE`). |
| appwrite.smtp.username | string | `""` | SMTP username (`_APP_SMTP_USERNAME`). |
| appwrite.system.emailAddress | string | `""` | Sender address for emails Appwrite sends (`_APP_SYSTEM_EMAIL_ADDRESS`). |
| appwrite.system.emailName | string | `"Appwrite"` | Sender name for emails Appwrite sends (`_APP_SYSTEM_EMAIL_NAME`). |
| appwrite.system.securityEmailAddress | string | `""` | Address shown to users for security issues (`_APP_EMAIL_SECURITY`). |
| appwrite.usageStats | bool | `true` | Collect usage statistics in ClickHouse (`_APP_USAGE_STATS`). |
| appwrite.workerPerCore | int | `6` | Swoole workers per CPU in the API (`_APP_WORKER_PER_CORE`). |
| clickhouse.affinity | object | `{}` | Affinity. Empty inherits `defaults.affinity`. |
| clickhouse.auth.database | string | `"appwrite"` | Database name. |
| clickhouse.auth.existingSecret | string | `""` | Existing Secret holding the password. |
| clickhouse.auth.password | string | `""` | Password. Generated and kept across upgrades when empty. |
| clickhouse.auth.passwordKey | string | `"clickhouse-password"` | Key in the Secret holding the password. |
| clickhouse.auth.username | string | `"appwrite"` | User. |
| clickhouse.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":true}` | Container security context. |
| clickhouse.enabled | bool | `true` | Deploy the built-in ClickHouse. |
| clickhouse.image.digest | string | `""` | Image digest. |
| clickhouse.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| clickhouse.image.registry | string | `"docker.io"` | Image registry. |
| clickhouse.image.repository | string | `"clickhouse/clickhouse-server"` | Image repository. |
| clickhouse.image.tag | string | `"26.4.3-alpine"` | Image tag. |
| clickhouse.nodeSelector | object | `{}` | Node selector. Empty inherits `defaults.nodeSelector`. |
| clickhouse.persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes. |
| clickhouse.persistence.annotations | object | `{}` | Annotations for the PersistentVolumeClaim. |
| clickhouse.persistence.enabled | bool | `true` | Persist data in a PersistentVolumeClaim. |
| clickhouse.persistence.size | string | `"10Gi"` | Volume size. |
| clickhouse.persistence.storageClass | string | `""` | Storage class. Empty uses the cluster default. |
| clickhouse.podAnnotations | object | `{}` | Pod annotations, merged over `defaults.podAnnotations`. |
| clickhouse.podLabels | object | `{}` | Pod labels, merged over `defaults.podLabels`. |
| clickhouse.podSecurityContext | object | `{"fsGroup":101,"fsGroupChangePolicy":"OnRootMismatch","runAsGroup":101,"runAsNonRoot":true,"runAsUser":101,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context. The image's `clickhouse` user is UID 101. |
| clickhouse.priorityClassName | string | `""` | Priority class. Empty inherits `defaults.priorityClassName`. |
| clickhouse.resources | object | `{"limits":{"memory":"2Gi"},"requests":{"cpu":"100m","memory":"512Mi"}}` | Resource requests and limits. |
| clickhouse.tolerations | list | `[]` | Tolerations. Empty inherits `defaults.tolerations`. |
| commonAnnotations | object | `{}` | Annotations added to every resource rendered by the chart. |
| commonLabels | object | `{}` | Labels added to every resource rendered by the chart. |
| console.affinity | object | `{}` | Affinity. Empty inherits `defaults.affinity`. |
| console.autoscaling.behavior | object | `{}` | HPA scaling behaviour. |
| console.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| console.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| console.autoscaling.minReplicas | int | `2` | Minimum replicas. |
| console.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| console.autoscaling.targetMemoryUtilizationPercentage | string | `""` | Target average memory utilisation, in percent. Empty disables the metric. |
| console.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":true}` | Container security context. |
| console.enabled | bool | `true` | Deploy the console. |
| console.env | object | `{"APPWRITE_ENDPOINT_SAME_ORIGIN":"true","VITE_CONSOLE_PROFILE":"self-hosted","VITE_GROWTH_ENDPOINT":"https://growth.appwrite.io/v1"}` | Environment variables for the console, as a map. |
| console.extraEnv | list | `[]` | Extra environment variables, as a list of EnvVar objects. |
| console.extraVolumeMounts | list | `[]` | Extra volume mounts for the main container. |
| console.extraVolumes | list | `[]` | Extra volumes. |
| console.image.digest | string | `""` | Image digest. |
| console.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| console.image.registry | string | `"docker.io"` | Image registry. |
| console.image.repository | string | `"appwrite/new"` | Image repository. |
| console.image.tag | string | `"1.1.159-self-hosted"` | Image tag. Pinned to the console that ships with the chart's appVersion. |
| console.livenessProbe.enabled | bool | `true` | Enable the liveness probe. |
| console.livenessProbe.failureThreshold | int | `3` |  |
| console.livenessProbe.periodSeconds | int | `20` |  |
| console.livenessProbe.timeoutSeconds | int | `5` |  |
| console.nodeSelector | object | `{}` | Node selector. Empty inherits `defaults.nodeSelector`. |
| console.pdb.enabled | bool | `true` | Create a PodDisruptionBudget when more than one replica can run. |
| console.pdb.maxUnavailable | int | `1` | Maximum unavailable pods. |
| console.pdb.minAvailable | string | `""` | Minimum available pods. Takes precedence over `maxUnavailable`. |
| console.podAnnotations | object | `{}` | Pod annotations, merged over `defaults.podAnnotations`. |
| console.podLabels | object | `{}` | Pod labels, merged over `defaults.podLabels`. |
| console.podSecurityContext | object | `{"fsGroup":1000,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context. The console image's `bun` user is UID 1000. |
| console.priorityClassName | string | `""` | Priority class. Empty inherits `defaults.priorityClassName`. |
| console.readinessProbe.enabled | bool | `true` | Enable the readiness probe. |
| console.readinessProbe.failureThreshold | int | `3` |  |
| console.readinessProbe.periodSeconds | int | `10` |  |
| console.readinessProbe.successThreshold | int | `1` |  |
| console.readinessProbe.timeoutSeconds | int | `5` |  |
| console.replicaCount | int | `1` | Number of console replicas. Ignored when autoscaling is enabled. |
| console.resources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"50m","memory":"128Mi"}}` | Resource requests and limits. |
| console.service.annotations | object | `{}` | Service annotations. |
| console.service.port | int | `80` | Service port. |
| console.service.type | string | `"ClusterIP"` | Service type. |
| console.startupProbe.enabled | bool | `true` | Enable the startup probe. |
| console.startupProbe.failureThreshold | int | `30` |  |
| console.startupProbe.periodSeconds | int | `5` |  |
| console.startupProbe.timeoutSeconds | int | `5` |  |
| console.terminationGracePeriodSeconds | int | `30` | Seconds to wait for in-flight requests on shutdown. |
| console.tolerations | list | `[]` | Tolerations. Empty inherits `defaults.tolerations`. |
| console.topologySpreadConstraints | list | `[]` | Topology spread constraints. Empty inherits `defaults.topologySpreadConstraints`. |
| console.updateStrategy | object | `{}` | Deployment update strategy. |
| containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":true}` | Container security context for every container running the Appwrite image. |
| defaults.affinity | object | `{}` | Affinity for every pod. |
| defaults.nodeSelector | object | `{}` | Node selector for every pod. |
| defaults.podAnnotations | object | `{}` | Annotations added to every pod. |
| defaults.podLabels | object | `{}` | Labels added to every pod. |
| defaults.priorityClassName | string | `""` | Priority class for every pod. |
| defaults.tolerations | list | `[]` | Tolerations for every pod. |
| defaults.topologySpreadConstraints | list | `[]` | Topology spread constraints for every pod. The component's selector labels are filled in when `labelSelector` is omitted. Leave empty for a soft spread across nodes on scalable components. |
| fullnameOverride | string | `""` | Override the fully qualified app name used in resource names. |
| geo.affinity | object | `{}` | Affinity. Empty inherits `defaults.affinity`. |
| geo.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":true}` | Container security context. |
| geo.enabled | bool | `true` | Deploy the geo service. When disabled, Appwrite skips geolocation. |
| geo.image.digest | string | `""` | Image digest. |
| geo.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| geo.image.registry | string | `"docker.io"` | Image registry. |
| geo.image.repository | string | `"appwrite/geo"` | Image repository. |
| geo.image.tag | string | `"0.3.1"` | Image tag. |
| geo.nodeSelector | object | `{}` | Node selector. Empty inherits `defaults.nodeSelector`. |
| geo.podAnnotations | object | `{}` | Pod annotations, merged over `defaults.podAnnotations`. |
| geo.podLabels | object | `{}` | Pod labels, merged over `defaults.podLabels`. |
| geo.podSecurityContext | object | `{"runAsGroup":82,"runAsNonRoot":true,"runAsUser":82,"seccompProfile":{"type":"RuntimeDefault"},"sysctls":[{"name":"net.ipv4.ip_unprivileged_port_start","value":"0"}]}` | Pod security context. The geo server listens on port 80, so the unprivileged port range is lowered for the pod instead of running as root. |
| geo.priorityClassName | string | `""` | Priority class. Empty inherits `defaults.priorityClassName`. |
| geo.replicaCount | int | `1` | Number of replicas. |
| geo.resources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"20m","memory":"128Mi"}}` | Resource requests and limits. |
| geo.tolerations | list | `[]` | Tolerations. Empty inherits `defaults.tolerations`. |
| global.imagePullSecrets | list | `[]` | Image pull secrets added to every pod, as a list of Secret names. |
| global.imageRegistry | string | `""` | Registry that replaces the registry of every image, e.g. a pull-through cache. |
| global.storageClass | string | `""` | Storage class for every PersistentVolumeClaim that doesn't set one. `-` means no class. |
| image.digest | string | `""` | Image digest (`sha256:...`). When set it pins the image and the tag is informational. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.registry | string | `"docker.io"` | Image registry. |
| image.repository | string | `"appwrite/appwrite"` | Image repository. |
| image.tag | string | `""` | Image tag. Defaults to the chart appVersion. |
| nameOverride | string | `""` | Override the chart name used in resource names. |
| networkPolicy.egress.dns | list | `[{"namespaceSelector":{},"podSelector":{"matchLabels":{"k8s-app":"kube-dns"}}}]` | DNS servers to allow (NetworkPolicyPeer) when egress is restricted. |
| networkPolicy.egress.enabled | bool | `false` | Restrict egress to DNS, pods of this release and `extraRules`. Off by default: Appwrite calls webhooks, SMTP servers, OAuth providers, the executor and other external services. |
| networkPolicy.egress.extraRules | list | `[]` | Extra egress rules (NetworkPolicyEgressRule) when egress is restricted. |
| networkPolicy.enabled | bool | `false` | Create NetworkPolicies. They only take effect with a CNI that enforces them. |
| networkPolicy.ingress.from | list | `[]` | Sources (NetworkPolicyPeer) allowed to reach the API, console and realtime, typically your ingress controller or Gateway. Empty allows any source. Pods of this release can always reach them. |
| persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes. Use ReadWriteMany (or S3 storage) to spread API and worker pods across nodes. |
| persistence.annotations | object | `{}` | Annotations for the PersistentVolumeClaim. |
| persistence.colocateReadWriteOnce | bool | `true` | With a ReadWriteOnce volume, schedule every pod that mounts it on the same node so the volume can be attached. |
| persistence.enabled | bool | `true` | Persist `/storage` in a PersistentVolumeClaim. When disabled every pod gets its own emptyDir, which only works with a single API and worker pod. |
| persistence.existingClaim | string | `""` | Use an existing PersistentVolumeClaim instead of creating one. |
| persistence.keep | bool | `true` | Keep the PersistentVolumeClaim when the release is uninstalled. |
| persistence.size | string | `"20Gi"` | Volume size. |
| persistence.storageClass | string | `""` | Storage class. Empty uses the cluster default. |
| podSecurityContext | object | `{"fsGroup":82,"fsGroupChangePolicy":"OnRootMismatch","runAsGroup":82,"runAsNonRoot":true,"runAsUser":82,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context for every pod running the Appwrite image. UID/GID 82 is `www-data`, which owns `/storage` in the image. |
| postgresql.affinity | object | `{}` | Affinity. Empty inherits `defaults.affinity`. |
| postgresql.auth.database | string | `"appwrite"` | Database name. |
| postgresql.auth.existingSecret | string | `""` | Existing Secret holding the password. |
| postgresql.auth.password | string | `""` | Password. Generated and kept across upgrades when empty. |
| postgresql.auth.passwordKey | string | `"postgres-password"` | Key in the Secret holding the password. |
| postgresql.auth.username | string | `"appwrite"` | Database user. |
| postgresql.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":true}` | Container security context. |
| postgresql.enabled | bool | `true` | Deploy the built-in PostgreSQL. |
| postgresql.extraConfig | object | `{}` | Extra PostgreSQL settings passed as `-c name=value`. |
| postgresql.image.digest | string | `""` | Image digest. |
| postgresql.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| postgresql.image.registry | string | `"docker.io"` | Image registry. |
| postgresql.image.repository | string | `"appwrite/postgres"` | Image repository. Appwrite's image is PostgreSQL 18 with the extensions Appwrite needs. |
| postgresql.image.tag | string | `"0.1.0"` | Image tag. |
| postgresql.maxConnections | string | `""` | `max_connections`. Defaults to `appwrite.database.connectionsMax` + 20. |
| postgresql.nodeSelector | object | `{}` | Node selector. Empty inherits `defaults.nodeSelector`. |
| postgresql.persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes. |
| postgresql.persistence.annotations | object | `{}` | Annotations for the PersistentVolumeClaim. |
| postgresql.persistence.enabled | bool | `true` | Persist data in a PersistentVolumeClaim. Data is lost on restart when disabled. |
| postgresql.persistence.size | string | `"10Gi"` | Volume size. |
| postgresql.persistence.storageClass | string | `""` | Storage class. Empty uses the cluster default. |
| postgresql.podAnnotations | object | `{}` | Pod annotations, merged over `defaults.podAnnotations`. |
| postgresql.podLabels | object | `{}` | Pod labels, merged over `defaults.podLabels`. |
| postgresql.podSecurityContext | object | `{"fsGroup":999,"fsGroupChangePolicy":"OnRootMismatch","runAsGroup":999,"runAsNonRoot":true,"runAsUser":999,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context. The image's `postgres` user is UID 999. |
| postgresql.priorityClassName | string | `""` | Priority class. Empty inherits `defaults.priorityClassName`. |
| postgresql.resources | object | `{"limits":{"memory":"2Gi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Resource requests and limits. |
| postgresql.tolerations | list | `[]` | Tolerations. Empty inherits `defaults.tolerations`. |
| realtime.affinity | object | `{}` | Affinity. Empty inherits `defaults.affinity`. |
| realtime.autoscaling.behavior | object | `{}` | HPA scaling behaviour. |
| realtime.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| realtime.autoscaling.maxReplicas | int | `10` | Maximum replicas. |
| realtime.autoscaling.minReplicas | int | `2` | Minimum replicas. |
| realtime.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| realtime.autoscaling.targetMemoryUtilizationPercentage | string | `""` | Target average memory utilisation, in percent. Empty disables the metric. |
| realtime.containerSecurityContext | object | `{}` | Container security context. Empty inherits `containerSecurityContext`. |
| realtime.cpuNum | string | `""` | CPUs Appwrite sizes its connection pools for (`_APP_CPU_NUM`). Derived from resources when empty. |
| realtime.enabled | bool | `true` | Deploy the realtime server. |
| realtime.extraEnv | list | `[]` | Extra environment variables for this component. |
| realtime.extraVolumeMounts | list | `[]` | Extra volume mounts for the main container. |
| realtime.extraVolumes | list | `[]` | Extra volumes for this component. |
| realtime.livenessProbe.enabled | bool | `true` | Enable the liveness probe. |
| realtime.livenessProbe.failureThreshold | int | `3` |  |
| realtime.livenessProbe.periodSeconds | int | `20` |  |
| realtime.livenessProbe.timeoutSeconds | int | `5` |  |
| realtime.nodeSelector | object | `{}` | Node selector. Empty inherits `defaults.nodeSelector`. |
| realtime.pdb.enabled | bool | `true` | Create a PodDisruptionBudget when more than one replica can run. |
| realtime.pdb.maxUnavailable | int | `1` | Maximum unavailable pods. |
| realtime.pdb.minAvailable | string | `""` | Minimum available pods. Takes precedence over `maxUnavailable`. |
| realtime.podAnnotations | object | `{}` | Pod annotations, merged over `defaults.podAnnotations`. |
| realtime.podLabels | object | `{}` | Pod labels, merged over `defaults.podLabels`. |
| realtime.podSecurityContext | object | `{}` | Pod security context. Empty inherits `podSecurityContext`. |
| realtime.preStopSleepSeconds | int | `5` | Seconds to sleep before shutdown so endpoints are removed first. |
| realtime.priorityClassName | string | `""` | Priority class. Empty inherits `defaults.priorityClassName`. |
| realtime.processes | int | `1` | Swoole worker processes per pod (`_APP_WORKERS_NUM`). Prefer more replicas over more processes. |
| realtime.readinessProbe.enabled | bool | `true` | Enable the readiness probe. |
| realtime.readinessProbe.failureThreshold | int | `3` |  |
| realtime.readinessProbe.periodSeconds | int | `10` |  |
| realtime.readinessProbe.successThreshold | int | `1` |  |
| realtime.readinessProbe.timeoutSeconds | int | `5` |  |
| realtime.replicaCount | int | `1` | Number of realtime replicas. Ignored when autoscaling is enabled. |
| realtime.resources | object | `{"limits":{"memory":"1Gi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Resource requests and limits. |
| realtime.service.annotations | object | `{}` | Service annotations. |
| realtime.service.port | int | `80` | Service port. |
| realtime.service.type | string | `"ClusterIP"` | Service type. |
| realtime.startupProbe.enabled | bool | `true` | Enable the startup probe. |
| realtime.startupProbe.failureThreshold | int | `60` |  |
| realtime.startupProbe.periodSeconds | int | `5` |  |
| realtime.startupProbe.timeoutSeconds | int | `5` |  |
| realtime.terminationGracePeriodSeconds | int | `30` | Seconds to wait on shutdown. Realtime drains for up to 15s before closing sockets. |
| realtime.tolerations | list | `[]` | Tolerations. Empty inherits `defaults.tolerations`. |
| realtime.topologySpreadConstraints | list | `[]` | Topology spread constraints. Empty inherits `defaults.topologySpreadConstraints`. |
| realtime.updateStrategy | object | `{}` | Deployment update strategy. |
| redis.affinity | object | `{}` | Affinity. Empty inherits `defaults.affinity`. |
| redis.auth.enabled | bool | `true` | Require a password. |
| redis.auth.existingSecret | string | `""` | Existing Secret holding the password. |
| redis.auth.password | string | `""` | Password. Generated and kept across upgrades when empty. |
| redis.auth.passwordKey | string | `"redis-password"` | Key in the Secret holding the password. |
| redis.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":true}` | Container security context. |
| redis.enabled | bool | `true` | Deploy the built-in Redis. |
| redis.image.digest | string | `""` | Image digest. |
| redis.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| redis.image.registry | string | `"docker.io"` | Image registry. |
| redis.image.repository | string | `"redis"` | Image repository. `valkey/valkey` works as a drop-in replacement. |
| redis.image.tag | string | `"7.4.7-alpine"` | Image tag. |
| redis.maxmemory | string | `"512mb"` | `maxmemory`. Keep it below the memory limit. |
| redis.maxmemoryPolicy | string | `"allkeys-lru"` | `maxmemory-policy`. Appwrite's Docker install uses `allkeys-lru`. |
| redis.nodeSelector | object | `{}` | Node selector. Empty inherits `defaults.nodeSelector`. |
| redis.persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes. |
| redis.persistence.annotations | object | `{}` | Annotations for the PersistentVolumeClaim. |
| redis.persistence.enabled | bool | `true` | Persist data in a PersistentVolumeClaim. |
| redis.persistence.size | string | `"2Gi"` | Volume size. |
| redis.persistence.storageClass | string | `""` | Storage class. Empty uses the cluster default. |
| redis.podAnnotations | object | `{}` | Pod annotations, merged over `defaults.podAnnotations`. |
| redis.podLabels | object | `{}` | Pod labels, merged over `defaults.podLabels`. |
| redis.podSecurityContext | object | `{"fsGroup":999,"fsGroupChangePolicy":"OnRootMismatch","runAsGroup":999,"runAsNonRoot":true,"runAsUser":999,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context. The image's `redis` user is UID 999. |
| redis.priorityClassName | string | `""` | Priority class. Empty inherits `defaults.priorityClassName`. |
| redis.resources | object | `{"limits":{"memory":"768Mi"},"requests":{"cpu":"50m","memory":"128Mi"}}` | Resource requests and limits. |
| redis.tolerations | list | `[]` | Tolerations. Empty inherits `defaults.tolerations`. |
| serviceAccount.annotations | object | `{}` | Annotations for the ServiceAccount (e.g. workload identity bindings). |
| serviceAccount.automountServiceAccountToken | bool | `false` | Mount the ServiceAccount token. Appwrite doesn't talk to the Kubernetes API. |
| serviceAccount.create | bool | `true` | Create a ServiceAccount for Appwrite pods. |
| serviceAccount.name | string | `""` | Name of the ServiceAccount. Defaults to the fullname when `create` is true, `default` otherwise. |
| tasks.affinity | object | `{}` | Affinity. Empty inherits `defaults.affinity`. |
| tasks.containerSecurityContext | object | `{}` | Container security context. Empty inherits `containerSecurityContext`. |
| tasks.extraEnv | list | `[]` | Extra environment variables for every task. |
| tasks.interval.enabled | bool | `true` | Run the interval task (domain verification, stale execution cleanup). |
| tasks.interval.resources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"20m","memory":"128Mi"}}` | Resource requests and limits. |
| tasks.maintenance.enabled | bool | `true` | Run the maintenance task (cleanup, certificate renewal). |
| tasks.maintenance.resources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"20m","memory":"128Mi"}}` | Resource requests and limits. |
| tasks.nodeSelector | object | `{}` | Node selector. Empty inherits `defaults.nodeSelector`. |
| tasks.podAnnotations | object | `{}` | Pod annotations, merged over `defaults.podAnnotations`. |
| tasks.podLabels | object | `{}` | Pod labels, merged over `defaults.podLabels`. |
| tasks.podSecurityContext | object | `{}` | Pod security context. Empty inherits `podSecurityContext`. |
| tasks.priorityClassName | string | `""` | Priority class. Empty inherits `defaults.priorityClassName`. |
| tasks.scheduler.enabled | bool | `true` | Run the scheduler for function, execution and message schedules. |
| tasks.scheduler.mode | string | `"combined"` | `combined` runs one scheduler pod. `separate` runs the functions, executions and messages schedulers and the resource-usage task as separate pods, each with these resources. |
| tasks.scheduler.resources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"50m","memory":"128Mi"}}` | Resource requests and limits. |
| tasks.terminationGracePeriodSeconds | int | `30` | Seconds to wait on shutdown. |
| tasks.tolerations | list | `[]` | Tolerations. Empty inherits `defaults.tolerations`. |
| tests.enabled | bool | `true` | Render `helm test` pods. |
| workers.affinity | object | `{}` | Affinity. Empty inherits `defaults.affinity`. |
| workers.combined.cpuNum | string | `""` | CPUs Appwrite sizes its connection pools for (`_APP_CPU_NUM`). Derived from resources when empty. |
| workers.combined.maxCoroutines | int | `78` | Coroutine budget used to size connection pools (`_APP_WORKER_MAX_COROUTINES`). The default matches the sum of every queue's concurrency. |
| workers.combined.processes | int | `1` | Worker processes per pod (`_APP_WORKERS_NUM`). |
| workers.combined.replicaCount | int | `1` | Replicas. Capped at 1, because the `databases` queue must have a single consumer; use `separate` or `grouped` to scale other queues. |
| workers.combined.resources | object | `{"limits":{"memory":"2Gi"},"requests":{"cpu":"250m","memory":"512Mi"}}` | Resource requests and limits. |
| workers.containerSecurityContext | object | `{}` | Container security context. Empty inherits `containerSecurityContext`. |
| workers.extraEnv | list | `[]` | Extra environment variables for every worker. |
| workers.extraVolumeMounts | list | `[]` | Extra volume mounts for every worker. |
| workers.extraVolumes | list | `[]` | Extra volumes for every worker. |
| workers.groups | object | `{}` | Deployments used when `mode` is `grouped`: a map of group name to `queues` (list of queue names, e.g. `stats-usage`) plus optional `replicaCount`, `processes`, `maxCoroutines`, `cpuNum`, `resources` and `autoscaling`. Every queue should be in exactly one group. |
| workers.mode | string | `"combined"` | How queues are spread over Deployments. `combined` runs one Deployment that consumes every queue. `separate` runs one Deployment per queue (configured under `queues`). `grouped` runs one Deployment per entry in `groups`, each consuming a list of queues. |
| workers.nodeSelector | object | `{}` | Node selector. Empty inherits `defaults.nodeSelector`. |
| workers.podAnnotations | object | `{}` | Pod annotations, merged over `defaults.podAnnotations`. |
| workers.podLabels | object | `{}` | Pod labels, merged over `defaults.podLabels`. |
| workers.podSecurityContext | object | `{}` | Pod security context. Empty inherits `podSecurityContext`. |
| workers.priorityClassName | string | `""` | Priority class. Empty inherits `defaults.priorityClassName`. |
| workers.queues.builds.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| workers.queues.builds.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| workers.queues.builds.autoscaling.minReplicas | int | `1` | Minimum replicas. |
| workers.queues.builds.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| workers.queues.builds.enabled | bool | `true` | Consume the `builds` queue. Function and site builds (needs an executor). |
| workers.queues.builds.maxCoroutines | int | `8` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.builds.replicaCount | int | `1` | Replicas. |
| workers.queues.builds.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.queues.certificates.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| workers.queues.certificates.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| workers.queues.certificates.autoscaling.minReplicas | int | `1` | Minimum replicas. |
| workers.queues.certificates.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| workers.queues.certificates.enabled | bool | `true` | Consume the `certificates` queue. Let's Encrypt certificates and custom domain verification. |
| workers.queues.certificates.maxCoroutines | int | `8` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.certificates.replicaCount | int | `1` | Replicas. |
| workers.queues.certificates.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.queues.databases.enabled | bool | `true` | Consume the `databases` queue. Database, collection, attribute and index changes. Must have a single consumer: `replicaCount` is capped at 1. |
| workers.queues.databases.maxCoroutines | int | `1` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.databases.replicaCount | int | `1` | Replicas. Capped at 1. |
| workers.queues.databases.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.queues.deletes.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| workers.queues.deletes.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| workers.queues.deletes.autoscaling.minReplicas | int | `1` | Minimum replicas. |
| workers.queues.deletes.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| workers.queues.deletes.enabled | bool | `true` | Consume the `deletes` queue. Deletes and cleanup. |
| workers.queues.deletes.maxCoroutines | int | `8` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.deletes.replicaCount | int | `1` | Replicas. |
| workers.queues.deletes.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.queues.executions.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| workers.queues.executions.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| workers.queues.executions.autoscaling.minReplicas | int | `1` | Minimum replicas. |
| workers.queues.executions.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| workers.queues.executions.enabled | bool | `true` | Consume the `executions` queue. Execution logs. |
| workers.queues.executions.maxCoroutines | int | `8` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.executions.replicaCount | int | `1` | Replicas. |
| workers.queues.executions.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.queues.functions.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| workers.queues.functions.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| workers.queues.functions.autoscaling.minReplicas | int | `1` | Minimum replicas. |
| workers.queues.functions.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| workers.queues.functions.enabled | bool | `true` | Consume the `functions` queue. Function executions (needs an executor). |
| workers.queues.functions.maxCoroutines | int | `8` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.functions.replicaCount | int | `1` | Replicas. |
| workers.queues.functions.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.queues.jobs.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| workers.queues.jobs.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| workers.queues.jobs.autoscaling.minReplicas | int | `1` | Minimum replicas. |
| workers.queues.jobs.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| workers.queues.jobs.enabled | bool | `true` | Consume the `jobs` queue. Build job events from the orchestrator. |
| workers.queues.jobs.maxCoroutines | int | `8` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.jobs.replicaCount | int | `1` | Replicas. |
| workers.queues.jobs.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.queues.mails.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| workers.queues.mails.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| workers.queues.mails.autoscaling.minReplicas | int | `1` | Minimum replicas. |
| workers.queues.mails.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| workers.queues.mails.enabled | bool | `true` | Consume the `mails` queue. Emails. |
| workers.queues.mails.maxCoroutines | int | `6` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.mails.replicaCount | int | `1` | Replicas. |
| workers.queues.mails.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.queues.messaging.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| workers.queues.messaging.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| workers.queues.messaging.autoscaling.minReplicas | int | `1` | Minimum replicas. |
| workers.queues.messaging.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| workers.queues.messaging.enabled | bool | `true` | Consume the `messaging` queue. Messaging (email, SMS, push providers). |
| workers.queues.messaging.maxCoroutines | int | `1` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.messaging.replicaCount | int | `1` | Replicas. |
| workers.queues.messaging.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.queues.migrations.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| workers.queues.migrations.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| workers.queues.migrations.autoscaling.minReplicas | int | `1` | Minimum replicas. |
| workers.queues.migrations.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| workers.queues.migrations.enabled | bool | `true` | Consume the `migrations` queue. Imports from other Appwrite instances and providers. |
| workers.queues.migrations.maxCoroutines | int | `1` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.migrations.replicaCount | int | `1` | Replicas. |
| workers.queues.migrations.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.queues.notifications.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| workers.queues.notifications.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| workers.queues.notifications.autoscaling.minReplicas | int | `1` | Minimum replicas. |
| workers.queues.notifications.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| workers.queues.notifications.enabled | bool | `true` | Consume the `notifications` queue. Push notifications. |
| workers.queues.notifications.maxCoroutines | int | `1` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.notifications.replicaCount | int | `1` | Replicas. |
| workers.queues.notifications.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.queues.screenshots.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| workers.queues.screenshots.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| workers.queues.screenshots.autoscaling.minReplicas | int | `1` | Minimum replicas. |
| workers.queues.screenshots.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| workers.queues.screenshots.enabled | bool | `true` | Consume the `screenshots` queue. Site screenshots (needs the browser service). |
| workers.queues.screenshots.maxCoroutines | int | `8` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.screenshots.replicaCount | int | `1` | Replicas. |
| workers.queues.screenshots.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.queues.statsResources.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| workers.queues.statsResources.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| workers.queues.statsResources.autoscaling.minReplicas | int | `1` | Minimum replicas. |
| workers.queues.statsResources.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| workers.queues.statsResources.enabled | bool | `true` | Consume the `stats-resources` queue. Periodic resource counts per project. |
| workers.queues.statsResources.maxCoroutines | int | `1` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.statsResources.replicaCount | int | `1` | Replicas. |
| workers.queues.statsResources.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.queues.statsUsage.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| workers.queues.statsUsage.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| workers.queues.statsUsage.autoscaling.minReplicas | int | `1` | Minimum replicas. |
| workers.queues.statsUsage.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| workers.queues.statsUsage.enabled | bool | `true` | Consume the `stats-usage` queue. Usage statistics written to ClickHouse after every request. |
| workers.queues.statsUsage.maxCoroutines | int | `8` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.statsUsage.replicaCount | int | `1` | Replicas. |
| workers.queues.statsUsage.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.queues.webhooks.autoscaling.enabled | bool | `false` | Create a HorizontalPodAutoscaler. |
| workers.queues.webhooks.autoscaling.maxReplicas | int | `5` | Maximum replicas. |
| workers.queues.webhooks.autoscaling.minReplicas | int | `1` | Minimum replicas. |
| workers.queues.webhooks.autoscaling.targetCPUUtilizationPercentage | int | `75` | Target average CPU utilisation, in percent. |
| workers.queues.webhooks.enabled | bool | `true` | Consume the `webhooks` queue. Webhook deliveries. |
| workers.queues.webhooks.maxCoroutines | int | `8` | Concurrent jobs per process (`_APP_WORKER_MAX_COROUTINES`). |
| workers.queues.webhooks.replicaCount | int | `1` | Replicas. |
| workers.queues.webhooks.resources | object | `{}` | Resource requests and limits. Empty inherits `workers.resources`. |
| workers.resources | object | `{"limits":{"memory":"1Gi"},"requests":{"cpu":"50m","memory":"192Mi"}}` | Resource requests and limits for `separate` and `grouped` Deployments that don't set their own. |
| workers.terminationGracePeriodSeconds | int | `45` | Seconds to let workers finish in-flight jobs on shutdown. The queue drains for up to 30s. |
| workers.tolerations | list | `[]` | Tolerations. Empty inherits `defaults.tolerations`. |
| workers.topologySpreadConstraints | list | `[]` | Topology spread constraints. Empty inherits `defaults.topologySpreadConstraints`. |

## License

BSD 3-Clause. See [LICENSE](https://github.com/levivannoort/helm-chart/blob/main/LICENSE).
