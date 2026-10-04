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
{{- if not $v.postgresql.enabled }}
{{- $errors = append $errors "postgresql.enabled=false is not supported yet: an external database can't be configured in this chart version." }}
{{- end }}
{{- if not $v.redis.enabled }}
{{- $errors = append $errors "redis.enabled=false is not supported yet: an external Redis can't be configured in this chart version." }}
{{- end }}
{{- if not $v.clickhouse.enabled }}
{{- $errors = append $errors "clickhouse.enabled=false is not supported yet: an external ClickHouse can't be configured in this chart version." }}
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
{{- range $k, $_ := $v.appwrite.config }}
{{- if not (regexMatch "^_APP_[A-Z0-9_]+$" $k) }}
{{- $errors = append $errors (printf "appwrite.config.%s: keys must be Appwrite variables matching ^_APP_[A-Z0-9_]+$." $k) }}
{{- end }}
{{- end }}
{{- if $errors }}
{{- fail (printf "\n\nInvalid values:\n  - %s\n" (join "\n  - " $errors)) }}
{{- end }}
{{- end }}
