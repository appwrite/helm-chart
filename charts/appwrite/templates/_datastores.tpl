{{/*
Connection settings for the main database, built-in or external, as YAML:
adapter, host, port, database, username, and secret (name/key) when a
password is configured.
*/}}
{{- define "appwrite.db" -}}
{{- $root := . }}
{{- if .Values.postgresql.enabled }}
{{- $a := .Values.postgresql.auth }}
adapter: postgresql
host: {{ include "appwrite.componentName" (dict "root" . "component" "postgresql") }}
port: "5432"
database: {{ $a.database }}
username: {{ $a.username }}
secret:
  name: {{ $a.existingSecret | default (include "appwrite.secretName" .) }}
  key: {{ ternary $a.passwordKey "postgres-password" (not (empty $a.existingSecret)) }}
{{- else }}
{{- $e := .Values.externalDatabase }}
{{- $ports := dict "postgresql" "5432" "mariadb" "3306" "mysql" "3306" "mongodb" "27017" }}
adapter: {{ $e.adapter }}
host: {{ $e.host }}
port: {{ $e.port | default (get $ports $e.adapter) | toString | quote }}
database: {{ $e.database }}
username: {{ $e.username }}
{{- include "appwrite.datastore.secret" (dict "root" . "config" $e "chartKey" "db-password") }}
{{- end }}
{{- end }}

{{/*
Redis connection settings, built-in or external.
*/}}
{{- define "appwrite.redis" -}}
{{- if .Values.redis.enabled }}
{{- $a := .Values.redis.auth }}
host: {{ include "appwrite.componentName" (dict "root" . "component" "redis") }}
port: "6379"
username: ""
{{- if $a.enabled }}
secret:
  name: {{ $a.existingSecret | default (include "appwrite.secretName" .) }}
  key: {{ ternary $a.passwordKey "redis-password" (not (empty $a.existingSecret)) }}
{{- end }}
{{- else }}
{{- $e := .Values.externalRedis }}
host: {{ $e.host }}
port: {{ $e.port | toString | quote }}
username: {{ $e.username | quote }}
{{- include "appwrite.datastore.secret" (dict "root" . "config" $e "chartKey" "redis-password") }}
{{- end }}
{{- end }}

{{/*
ClickHouse connection settings, built-in or external: scheme, address
(host:port), database, username, secret.
*/}}
{{- define "appwrite.clickhouse" -}}
{{- if .Values.clickhouse.enabled }}
{{- $a := .Values.clickhouse.auth }}
scheme: http
address: {{ include "appwrite.componentName" (dict "root" . "component" "clickhouse") }}:8123
database: {{ $a.database }}
username: {{ $a.username }}
secret:
  name: {{ $a.existingSecret | default (include "appwrite.secretName" .) }}
  key: {{ ternary $a.passwordKey "clickhouse-password" (not (empty $a.existingSecret)) }}
{{- else }}
{{- $e := .Values.externalClickhouse }}
{{- $url := urlParse ($e.url | default "http://clickhouse:8123") }}
{{- $port := ternary "8443" "8123" (eq $url.scheme "https") }}
scheme: {{ $url.scheme }}
address: {{ ternary $url.host (printf "%s:%s" $url.host $port) (contains ":" $url.host) }}
database: {{ $e.database }}
username: {{ $e.username }}
{{- include "appwrite.datastore.secret" (dict "root" . "config" $e "chartKey" "clickhouse-password") }}
{{- end }}
{{- end }}

{{/*
`secret:` block for an external service's password: its existing Secret, or
the chart Secret when the password is set inline. Nothing when there's no
password.
*/}}
{{- define "appwrite.datastore.secret" -}}
{{- $c := .config }}
{{- if $c.existingSecret }}
secret:
  name: {{ $c.existingSecret }}
  key: {{ $c.passwordKey }}
{{- else if $c.password }}
secret:
  name: {{ include "appwrite.secretName" .root }}
  key: {{ .chartKey }}
{{- end }}
{{- end }}

{{/*
Optional secondary database (documentsDb or vectorsDb) password secret.
*/}}
{{- define "appwrite.secondaryDb.secret" -}}
{{- include "appwrite.datastore.secret" . }}
{{- end }}
