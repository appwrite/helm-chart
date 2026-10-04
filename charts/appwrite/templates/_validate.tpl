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
{{- if $v.postgresql.enabled }}
{{- if $v.externalDatabase.host }}
{{- $errors = append $errors "externalDatabase.host is set while postgresql.enabled is true: disable the built-in PostgreSQL to use an external database." }}
{{- end }}
{{- else }}
{{- if not $v.externalDatabase.host }}
{{- $errors = append $errors "externalDatabase.host is required when postgresql.enabled is false." }}
{{- end }}
{{- if not (or $v.externalDatabase.password $v.externalDatabase.existingSecret) }}
{{- $errors = append $errors "externalDatabase needs a password or an existingSecret." }}
{{- end }}
{{- end }}
{{- if $v.redis.enabled }}
{{- if $v.externalRedis.host }}
{{- $errors = append $errors "externalRedis.host is set while redis.enabled is true: disable the built-in Redis to use an external one." }}
{{- end }}
{{- else if not $v.externalRedis.host }}
{{- $errors = append $errors "externalRedis.host is required when redis.enabled is false." }}
{{- end }}
{{- if $v.clickhouse.enabled }}
{{- if $v.externalClickhouse.url }}
{{- $errors = append $errors "externalClickhouse.url is set while clickhouse.enabled is true: disable the built-in ClickHouse to use an external one." }}
{{- end }}
{{- else if not (regexMatch "^https?://[^/]+/?$" ($v.externalClickhouse.url | default "")) }}
{{- $errors = append $errors "externalClickhouse.url must be an http(s) URL without a path, e.g. https://clickhouse.example.com:8443, when clickhouse.enabled is false." }}
{{- end }}
{{- with $v.appwrite.documentsDb }}
{{- if and .enabled (not .host) }}
{{- $errors = append $errors "appwrite.documentsDb.host is required when DocumentsDB is enabled." }}
{{- end }}
{{- end }}
{{- with $v.appwrite.vectorsDb }}
{{- if and .enabled (not .host) (not $v.postgresql.enabled) (ne $v.externalDatabase.adapter "postgresql") }}
{{- $errors = append $errors "appwrite.vectorsDb.host is required when the main database isn't PostgreSQL." }}
{{- end }}
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
{{- if and (has "databases" ($g.queues | default list)) (or (gt (int ($g.replicaCount | default 1)) 1) (and $g.autoscaling $g.autoscaling.enabled)) }}
{{- $errors = append $errors (printf "workers.groups.%s consumes the databases queue, which must have a single consumer: set replicaCount to 1 and disable autoscaling, or move databases to its own group." $group) }}
{{- end }}
{{- end }}
{{- end }}
{{- $storage := $v.appwrite.storage }}
{{- if eq $storage.device "s3" }}
{{- if not $storage.s3.bucket }}
{{- $errors = append $errors "appwrite.storage.s3.bucket is required when appwrite.storage.device is s3." }}
{{- end }}
{{- if not (or $storage.s3.existingSecret (and $storage.s3.accessKey $storage.s3.secretKey)) }}
{{- $errors = append $errors "appwrite.storage.s3 needs accessKey and secretKey, or an existingSecret." }}
{{- end }}
{{- end }}
{{- if $v.compute.enabled }}
{{- if not $v.compute.executor.host }}
{{- $errors = append $errors "compute.executor.host is required when compute.enabled is true." }}
{{- end }}
{{- if not $v.compute.orchestrator.host }}
{{- $errors = append $errors "compute.orchestrator.host is required when compute.enabled is true." }}
{{- end }}
{{- if ne $storage.device "s3" }}
{{- $errors = append $errors "compute.enabled needs appwrite.storage.device=s3: the executor and orchestrator run outside the cluster and can't reach the /storage volume." }}
{{- end }}
{{- end }}
{{- if and $v.assistant.enabled (not (or $v.assistant.openaiApiKey $v.assistant.existingSecret)) }}
{{- $errors = append $errors "assistant.enabled needs assistant.openaiApiKey or assistant.existingSecret." }}
{{- end }}
{{- if and $v.mqtt.enabled (not $v.redis.enabled) $v.externalRedis.username }}
{{- $errors = append $errors "mqtt.enabled doesn't work with externalRedis.username: Appwrite's MQTT server ignores Redis ACL users. Use the default user." }}
{{- end }}
{{- if and $v.httpRoute.enabled (not $v.httpRoute.parentRefs) }}
{{- $errors = append $errors "httpRoute.parentRefs is required when httpRoute.enabled is true: name the Gateway to attach to." }}
{{- end }}
{{- range $k, $_ := $v.appwrite.config }}
{{- if not (regexMatch "^_APP_[A-Z0-9_]+$" $k) }}
{{- $errors = append $errors (printf "appwrite.config.%s: keys must be Appwrite variables matching ^_APP_[A-Z0-9_]+$." $k) }}
{{- end }}
{{- end }}
{{- $installed := include "appwrite.installedVersion" . }}
{{- $target := include "appwrite.version" . }}
{{- if and $installed (not $v.migrations.allowDowngrade) (regexMatch "^v?[0-9]+\\.[0-9]+\\.[0-9]+" $installed) (regexMatch "^v?[0-9]+\\.[0-9]+\\.[0-9]+" $target) }}
{{- if semverCompare (printf "<%s" $installed) $target }}
{{- $errors = append $errors (printf "Appwrite %s is installed and this would downgrade it to %s. Appwrite can't migrate data backwards; restore a backup taken before the upgrade instead, or set migrations.allowDowngrade=true." $installed $target) }}
{{- end }}
{{- end }}
{{- if $errors }}
{{- fail (printf "\n\nInvalid values:\n  - %s\n" (join "\n  - " $errors)) }}
{{- end }}
{{- end }}
