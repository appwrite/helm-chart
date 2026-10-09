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
{{- if and (has "databases" ($g.queues | default list)) (or (gt (int ($g.replicaCount | default 1)) 1) (gt (int ($g.processes | default 1)) 1) (and $g.autoscaling $g.autoscaling.enabled)) }}
{{- $errors = append $errors (printf "workers.groups.%s consumes the databases queue, which must have a single consumer: set replicaCount and processes to 1 and disable autoscaling, or move databases to its own group." $group) }}
{{- end }}
{{- end }}
{{- $missing := list }}
{{- range $known }}
{{- if not (hasKey $seen .) }}{{ $missing = append $missing . }}{{ end }}
{{- end }}
{{- if and $v.workers.groups $missing }}
{{- $errors = append $errors (printf "workers.groups: no group consumes %s; every queue needs exactly one group, or its jobs pile up in Redis." (join ", " (sortAlpha $missing))) }}
{{- end }}
{{- else if and (eq $v.workers.mode "combined") (gt (int $v.workers.combined.processes) 1) }}
{{- $errors = append $errors "workers.combined.processes must be 1: the combined worker consumes the databases queue, which must have a single consumer. Use workers.mode=grouped or separate to scale other queues." }}
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
{{- $e := $v.compute.executor }}
{{- if eq $e.mode "external" }}
{{- if not $e.host }}
{{- $errors = append $errors "compute.executor.host is required when compute.executor.mode is external." }}
{{- end }}
{{- else }}
{{- if $e.host }}
{{- $errors = append $errors "compute.executor.host is set, but compute.executor.mode is cluster, where the chart runs the executor itself. Set compute.executor.mode=external to use the executor at that host." }}
{{- end }}
{{- if not (or $e.privileged $e.runtimeClassName) }}
{{- $errors = append $errors "The in-cluster executor runs Docker-in-Docker, which needs a privileged container: root on its node. Set compute.executor.privileged=true to accept that (and give the executor nodes of its own), set compute.executor.runtimeClassName to a runtime that runs Docker without it (Sysbox), or set compute.executor.mode=external to run the executor on a Docker host. See docs/executor.md." }}
{{- end }}
{{- $ns := include "appwrite.executor.namespace" . }}
{{- if eq $ns .Release.Namespace }}
{{- $errors = append $errors "compute.executor.namespace must differ from the release namespace: the executor needs the privileged Pod Security Standard, so it gets a namespace of its own." }}
{{- else if and (include "appwrite.builds.inCluster" .) (eq $ns (include "appwrite.builds.namespace" .)) }}
{{- $errors = append $errors "compute.executor.namespace must differ from compute.builds.namespace: build pods are kept to the baseline Pod Security Standard, the executor needs privileged." }}
{{- end }}
{{- if and (not $e.existingSecret) (or $v.compute.secrets.existingSecret $v.appwrite.storage.s3.existingSecret) }}
{{- $errors = append $errors "compute.executor.existingSecret is required when compute.secrets.existingSecret or appwrite.storage.s3.existingSecret is set: the executor runs in another namespace and can't read them. Create a Secret there with the keys executor-secret, s3-access-key and s3-secret-key." }}
{{- end }}
{{- end }}
{{- if eq $v.compute.orchestrator.mode "external" }}
{{- if not $v.compute.orchestrator.host }}
{{- $errors = append $errors "compute.orchestrator.host is required when compute.orchestrator.mode is external." }}
{{- end }}
{{- else if eq (include "appwrite.builds.namespace" .) .Release.Namespace }}
{{- $errors = append $errors "compute.builds.namespace must differ from the release namespace: build pods need the baseline Pod Security Standard, so they get a namespace of their own." }}
{{- end }}
{{- if ne $storage.device "s3" }}
{{- $errors = append $errors "compute.enabled needs appwrite.storage.device=s3: builds and the executor exchange code and build output through object storage." }}
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
{{- range $field := list "config" "secretConfig" }}
{{- range $k, $_ := get $v.appwrite $field | default dict }}
{{- if not (regexMatch "^_APP_[A-Z0-9_]+$" $k) }}
{{- $errors = append $errors (printf "appwrite.%s.%s: keys must be Appwrite variables matching ^_APP_[A-Z0-9_]+$." $field $k) }}
{{- end }}
{{- end }}
{{- end }}
{{- if and $v.postgresql.enabled $v.postgresql.maxConnections (lt (int $v.postgresql.maxConnections) (int $v.appwrite.database.connectionsMax)) }}
{{- $errors = append $errors (printf "postgresql.maxConnections (%v) is below appwrite.database.connectionsMax (%v): Appwrite would open more connections than PostgreSQL accepts." $v.postgresql.maxConnections $v.appwrite.database.connectionsMax) }}
{{- end }}
{{- range $store := list "postgresql" "redis" "clickhouse" }}
{{- $name := include "appwrite.componentName" (dict "root" $ "component" $store) }}
{{- if and (get $v $store).enabled (gt (len $name) 52) }}
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
{{- if $errors }}
{{- fail (printf "\n\nInvalid values:\n  - %s\n" (join "\n  - " $errors)) }}
{{- end }}
{{- end }}
