{{/*
Fail early on configurations that would install but not work. Included from
configmap-env.yaml so it also runs under `helm template`.
*/}}
{{- define "appwrite.validate" -}}
{{- $v := .Values }}
{{- $errors := list }}
{{- if not $v.appwrite.domain }}
{{- $errors = append $errors "appwrite.domain is required: set it to the hostname users reach Appwrite on, e.g. --set appwrite.domain=appwrite.example.com." }}
{{- end }}
{{- if not $v.appwrite.certificatesEmail }}
{{- $errors = append $errors "appwrite.certificatesEmail is required: the certificates worker refuses to start without it." }}
{{- end }}
{{- $hasValue := dict }}
{{- range $name, $ref := dict "database.password" $v.database.password "redis.password" $v.redis.password "clickhouse.password" $v.clickhouse.password "documentsDb.password" $v.documentsDb.password "vectorsDb.password" $v.vectorsDb.password "smtp.password" $v.smtp.password "storage.s3.accessKeyId" $v.storage.s3.accessKeyId "storage.s3.secretAccessKey" $v.storage.s3.secretAccessKey }}
{{- $_ := set $hasValue $name (or $ref.value $ref.secretName) }}
{{- if and $ref.secretName (not $ref.secretKey) }}
{{- $errors = append $errors (printf "%s.secretKey is required with %s.secretName: name the key in the Secret." $name $name) }}
{{- end }}
{{- end }}
{{- if eq $v.database.mode "builtin" }}
{{- if ne $v.database.adapter "postgresql" }}
{{- $errors = append $errors (printf "database.adapter is %s, but the built-in database is PostgreSQL: set database.mode=external to use %s." $v.database.adapter $v.database.adapter) }}
{{- end }}
{{- if $v.database.external.host }}
{{- $errors = append $errors "database.external.host is set while database.mode is builtin: set database.mode=external to use it." }}
{{- end }}
{{- else }}
{{- if not $v.database.external.host }}
{{- $errors = append $errors "database.external.host is required when database.mode is external." }}
{{- end }}
{{- if not (get $hasValue "database.password") }}
{{- $errors = append $errors "database.password needs a value or a secretName when database.mode is external." }}
{{- end }}
{{- end }}
{{- if eq $v.redis.mode "builtin" }}
{{- if $v.redis.external.host }}
{{- $errors = append $errors "redis.external.host is set while redis.mode is builtin: set redis.mode=external to use it." }}
{{- end }}
{{- if $v.redis.username }}
{{- $errors = append $errors "redis.username only applies to an external Redis: the built-in one has no ACL users." }}
{{- end }}
{{- else if not $v.redis.external.host }}
{{- $errors = append $errors "redis.external.host is required when redis.mode is external." }}
{{- end }}
{{- if eq $v.clickhouse.mode "builtin" }}
{{- if $v.clickhouse.external.url }}
{{- $errors = append $errors "clickhouse.external.url is set while clickhouse.mode is builtin: set clickhouse.mode=external to use it." }}
{{- end }}
{{- else if not (regexMatch "^https?://[^/]+/?$" ($v.clickhouse.external.url | default "")) }}
{{- $errors = append $errors "clickhouse.external.url must be an http(s) URL without a path, e.g. https://clickhouse.example.com:8443, when clickhouse.mode is external." }}
{{- end }}
{{- if and $v.documentsDb.enabled (not $v.documentsDb.host) }}
{{- $errors = append $errors "documentsDb.host is required when DocumentsDB is enabled." }}
{{- end }}
{{- if and $v.vectorsDb.enabled (not $v.vectorsDb.host) (ne $v.database.mode "builtin") (ne $v.database.adapter "postgresql") }}
{{- $errors = append $errors "vectorsDb.host is required when the main database isn't PostgreSQL." }}
{{- end }}
{{- if eq $v.workers.mode "grouped" }}
{{- $catalog := include "appwrite.workers.catalog" . | fromYaml }}
{{- $known := list }}
{{- range $catalog }}{{ $known = append $known .name }}{{ end }}
{{- $seen := dict }}
{{- if not $v.workers.groups }}
{{- $errors = append $errors "workers.mode=grouped needs at least one entry in workers.groups." }}
{{- end }}
{{- range $group, $g := $v.workers.groups }}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $group) }}
{{- $errors = append $errors (printf "workers.groups.%s: group names must be lowercase alphanumerics and dashes." $group) }}
{{- end }}
{{- if not $g.queues }}
{{- $errors = append $errors (printf "workers.groups.%s.queues must list at least one queue." $group) }}
{{- end }}
{{- range $g.queues }}
{{- if not (has . $known) }}
{{- $errors = append $errors (printf "workers.groups.%s: unknown queue %q; valid queues: %s." $group . (join ", " (sortAlpha $known))) }}
{{- else if hasKey $seen . }}
{{- $errors = append $errors (printf "workers.groups: queue %q is in both %s and %s; each queue needs exactly one group." . (get $seen .) $group) }}
{{- else }}
{{- $_ := set $seen . $group }}
{{- end }}
{{- end }}
{{- if and (has "databases" ($g.queues | default list)) (or (gt (int ($g.replicaCount | default 1)) 1) (gt (int ($g.processes | default 1)) 1) (and $g.autoscaling $g.autoscaling.enabled)) }}
{{- $errors = append $errors (printf "workers.groups.%s consumes the databases queue, which must have a single consumer: set replicaCount and processes to 1 and disable autoscaling, or move databases to its own group." $group) }}
{{- end }}
{{- end }}
{{- $missing := list }}
{{- range $catalog }}
{{- if not (or .optional (hasKey $seen .name)) }}{{ $missing = append $missing .name }}{{ end }}
{{- end }}
{{- if and $v.workers.groups $missing }}
{{- $errors = append $errors (printf "workers.groups: no group consumes %s; every queue needs exactly one group, or its jobs pile up in Redis." (join ", " (sortAlpha $missing))) }}
{{- end }}
{{- else if and (eq $v.workers.mode "combined") (gt (int $v.workers.combined.processes) 1) }}
{{- $errors = append $errors "workers.combined.processes must be 1: the combined worker consumes the databases queue, which must have a single consumer. Use workers.mode=grouped or separate to scale other queues." }}
{{- end }}
{{- $storage := $v.storage }}
{{- if eq $storage.device "s3" }}
{{- if not $storage.s3.bucket }}
{{- $errors = append $errors "storage.s3.bucket is required when storage.device is s3." }}
{{- end }}
{{- if and (eq $storage.s3.mode "external") (not (and (get $hasValue "storage.s3.accessKeyId") (get $hasValue "storage.s3.secretAccessKey"))) }}
{{- $errors = append $errors "storage.s3.accessKeyId and storage.s3.secretAccessKey need a value or a secretName with storage.s3.mode external." }}
{{- end }}
{{- end }}
{{- if $v.compute.enabled }}
{{- $e := $v.compute.executor }}
{{- if not (or $e.privileged $e.runtimeClassName) }}
{{- $errors = append $errors "The executor runs Docker-in-Docker, which needs a privileged container: root on its node. Set compute.executor.privileged=true to accept that (and give the executor nodes of its own), or set compute.executor.runtimeClassName to a runtime that runs Docker without it (Sysbox). See docs/executor.md." }}
{{- end }}
{{- $ns := include "appwrite.executor.namespace" . }}
{{- $builds := include "appwrite.builds.namespace" . }}
{{- if eq $builds .Release.Namespace }}
{{- $errors = append $errors "compute.builds.namespace must differ from the release namespace: build pods need the baseline Pod Security Standard, so they get a namespace of their own." }}
{{- end }}
{{- if eq $ns .Release.Namespace }}
{{- $errors = append $errors "compute.executor.namespace must differ from the release namespace: the executor needs the privileged Pod Security Standard, so it gets a namespace of its own." }}
{{- else if eq $ns $builds }}
{{- $errors = append $errors "compute.executor.namespace must differ from compute.builds.namespace: build pods are kept to the baseline Pod Security Standard, the executor needs privileged." }}
{{- end }}
{{- if and (not $e.existingSecret) (or $v.compute.secrets.existingSecret $storage.s3.accessKeyId.secretName $storage.s3.secretAccessKey.secretName) }}
{{- $errors = append $errors "compute.executor.existingSecret is required when compute.secrets.existingSecret or an S3 secretName (storage.s3.accessKeyId, storage.s3.secretAccessKey) is set: the executor runs in another namespace and can't read them. Create a Secret there with the keys executor-secret, s3-access-key and s3-secret-key." }}
{{- end }}
{{- if and (not $v.compute.secrets.existingSecret) (eq $v.compute.secrets.orchestratorSecret "your-secret-key") }}
{{- $errors = append $errors "compute.secrets.orchestratorSecret is Appwrite's public placeholder, which Appwrite 2.6.2 refuses for job callbacks, so every build would fail. Leave it empty for the chart to generate one, or set a random value." }}
{{- end }}
{{- if ne $storage.device "s3" }}
{{- $errors = append $errors "compute.enabled needs storage.device=s3: builds and the executor exchange code and build output through object storage. Keep the default (s3, with the built-in object store), or set compute.enabled=false to store files on the local volume without Functions and Sites." }}
{{- end }}
{{- end }}
{{- if and $v.mqtt.enabled $v.redis.username }}
{{- $errors = append $errors "mqtt.enabled doesn't work with redis.username: Appwrite's MQTT server ignores Redis ACL users. Use the default user." }}
{{- end }}
{{- if and $v.httpRoute.enabled (not $v.httpRoute.parentRefs) }}
{{- $errors = append $errors "httpRoute.parentRefs is required when httpRoute.enabled is true: name the Gateway to attach to." }}
{{- end }}
{{- range $field := list "config" "secretConfig" }}
{{- range $k, $_ := get $v.appwrite $field | default dict }}
{{- if not (regexMatch "^_APP_[A-Z0-9_]+$" $k) }}
{{- $errors = append $errors (printf "appwrite.%s.%s: keys must be Appwrite variables matching ^_APP_[A-Z0-9_]+$." $field $k) }}
{{- end }}
{{- end }}
{{- end }}
{{- if and (eq $v.database.mode "builtin") $v.database.builtin.maxConnections (lt (int $v.database.builtin.maxConnections) (int $v.database.connectionsMax)) }}
{{- $errors = append $errors (printf "database.builtin.maxConnections (%v) is below database.connectionsMax (%v): Appwrite would open more connections than PostgreSQL accepts." $v.database.builtin.maxConnections $v.database.connectionsMax) }}
{{- end }}
{{- $statefulSets := dict "postgresql" (eq $v.database.mode "builtin") "redis" (eq $v.redis.mode "builtin") "clickhouse" (eq $v.clickhouse.mode "builtin") "seaweedfs" (include "appwrite.s3.builtin" . | eq "true") }}
{{- range $store, $builtin := $statefulSets }}
{{- $name := include "appwrite.componentName" (dict "root" $ "component" $store) }}
{{- if and $builtin (gt (len $name) 52) }}
{{- $errors = append $errors (printf "StatefulSet name %q is longer than 52 characters, which breaks its pods' controller-revision-hash label: use a shorter release name or fullnameOverride." $name) }}
{{- end }}
{{- end }}
{{- $installed := include "appwrite.installedVersion" . }}
{{- $target := include "appwrite.version" . }}
{{- if and $installed (not $v.migrations.allowDowngrade) (regexMatch "^v?[0-9]+\\.[0-9]+\\.[0-9]+" $installed) (regexMatch "^v?[0-9]+\\.[0-9]+\\.[0-9]+" $target) }}
{{- if semverCompare (printf "<%s" $installed) $target }}
{{- $errors = append $errors (printf "Appwrite %s is installed and this would downgrade it to %s. Appwrite can't migrate data backwards; restore a backup taken before the upgrade instead, or set migrations.allowDowngrade=true." $installed $target) }}
{{- end }}
{{- end }}
{{- $supported := regexFind "^[0-9]+" (trimPrefix "v" (toString .Chart.AppVersion)) }}
{{- $major := regexFind "^[0-9]+" (trimPrefix "v" $target) }}
{{- if and $major (ne $major $supported) (not $v.image.allowUnsupportedVersion) }}
{{- $errors = append $errors (printf "image.tag %s is Appwrite %s.x, but this chart is written for Appwrite %s.x (%s): its defaults and migrations are untested with another major version. Use a chart release for that version, or set image.allowUnsupportedVersion=true." $target $major $supported .Chart.AppVersion) }}
{{- end }}
{{- $errors = concat $errors (include "appwrite.deprecations" . | fromJsonArray) }}
{{- if $errors }}
{{- fail (printf "\n\nInvalid values:\n  - %s\n" (join "\n  - " $errors)) }}
{{- end }}
{{- end }}
