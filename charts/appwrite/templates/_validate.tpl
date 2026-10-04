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
{{- range $k, $_ := $v.appwrite.config }}
{{- if not (regexMatch "^_APP_[A-Z0-9_]+$" $k) }}
{{- $errors = append $errors (printf "appwrite.config.%s: keys must be Appwrite variables matching ^_APP_[A-Z0-9_]+$." $k) }}
{{- end }}
{{- end }}
{{- if $errors }}
{{- fail (printf "\n\nInvalid values:\n  - %s\n" (join "\n  - " $errors)) }}
{{- end }}
{{- end }}
