{{/*
Environment shared by every Appwrite pod, as a dict of strings. Rendered into
the env ConfigMap. Precedence, lowest first:
  1. files/env-defaults.yaml (what the Docker installer writes to .env)
  2. values computed by the chart (domains, internal service URLs, ...)
  3. appwrite.config
*/}}
{{- define "appwrite.env.config" -}}
{{- $root := . }}
{{- $v := .Values.appwrite }}
{{- $fullname := include "appwrite.fullname" . }}
{{- $domain := $v.domain | default "localhost" }}
{{- $enabled := dict "true" "enabled" "false" "disabled" }}
{{- $env := .Files.Get "files/env-defaults.yaml" | fromYaml | default dict }}
{{- $apiHost := include "appwrite.api.host" . }}

{{- $computed := dict
  "_APP_ENV" "production"
  "_APP_DOMAIN" $domain
  "_APP_CONSOLE_DOMAIN" ($v.consoleDomain | default $domain)
  "_APP_DOMAIN_FUNCTIONS" ($v.functionsDomain | default (printf "functions.%s" $domain))
  "_APP_DOMAIN_SITES" ($v.sitesDomain | default (printf "sites.%s" $domain))
  "_APP_DOMAIN_TARGET_CNAME" ($v.domainTargets.cname | default $domain)
  "_APP_DOMAIN_TARGET_A" $v.domainTargets.a
  "_APP_DOMAIN_TARGET_AAAA" $v.domainTargets.aaaa
  "_APP_DOMAIN_TARGET_CAA" $v.domainTargets.caa
  "_APP_OPTIONS_FORCE_HTTPS" (get $enabled ($v.forceHttps | toString))
  "_APP_OPTIONS_ROUTER_FORCE_HTTPS" (get $enabled ($v.forceHttps | toString))
  "_APP_OPTIONS_ROUTER_PROTECTION" (get $enabled ($v.routerProtection | toString))
  "_APP_ROUTER_AUTO_CERTIFICATES" (get $enabled ($v.autoCertificates | toString))
  "_APP_EMAIL_CERTIFICATES" $v.certificatesEmail
  "_APP_LOGGING_FORMAT" $v.logFormat
  "_APP_USAGE_STATS" (get $enabled ($v.usageStats | toString))
  "_APP_WORKER_PER_CORE" ($v.workerPerCore | toString)
  "_APP_CONSOLE_WHITELIST_ROOT" (get $enabled ($v.console.whitelistRoot | toString))
  "_APP_CONSOLE_WHITELIST_EMAILS" (join "," $v.console.whitelistEmails)
  "_APP_CONSOLE_WHITELIST_IPS" (join "," $v.console.whitelistIPs)
  "_APP_SYSTEM_EMAIL_NAME" $v.system.emailName
  "_APP_SYSTEM_EMAIL_ADDRESS" ($v.system.emailAddress | default (printf "noreply@%s" $domain))
  "_APP_EMAIL_SECURITY" $v.system.securityEmailAddress
  "_APP_CONNECTIONS_MAX" ($v.database.connectionsMax | toString)
  "_APP_POOL_CLIENTS" ($v.database.poolClients | toString)
  "_APP_SMTP_HOST" $v.smtp.host
  "_APP_SMTP_PORT" ($v.smtp.port | toString)
  "_APP_SMTP_SECURE" $v.smtp.secure
  "_APP_SMTP_USERNAME" $v.smtp.username
  "_APP_MIGRATION_HOST" $apiHost
  "_APP_WORKER_SCREENSHOTS_ROUTER" (printf "http://%s" $apiHost)
  "_APP_JOBS_ENDPOINT" (printf "http://%s" $apiHost)
  "_APP_GEO_ENDPOINT" (ternary (printf "http://%s/v1" (include "appwrite.componentName" (dict "root" . "component" "geo"))) "" .Values.geo.enabled)
}}

{{- /* Main database */}}
{{- $db := include "appwrite.db" . | fromYaml }}
{{- $_ := set $computed "_APP_DB_ADAPTER" $db.adapter }}
{{- $_ := set $computed "_APP_DB_HOST" $db.host }}
{{- $_ := set $computed "_APP_DB_PORT" ($db.port | toString) }}
{{- $_ := set $computed "_APP_DB_SCHEMA" $db.database }}
{{- $_ := set $computed "_APP_DB_USER" $db.username }}

{{- /* Redis */}}
{{- $redis := include "appwrite.redis" . | fromYaml }}
{{- $_ := set $computed "_APP_REDIS_HOST" $redis.host }}
{{- $_ := set $computed "_APP_REDIS_PORT" ($redis.port | toString) }}
{{- $_ := set $computed "_APP_REDIS_USER" ($redis.username | default "") }}

{{- /* Optional DocumentsDB (MongoDB) and VectorsDB (PostgreSQL) databases */}}
{{- $docs := $v.documentsDb }}
{{- $_ := set $computed "_APP_DOCUMENTSDB" (get $enabled ($docs.enabled | toString)) }}
{{- if $docs.enabled }}
{{- $_ := set $computed "_APP_DB_ADAPTER_DOCUMENTSDB" "mongodb" }}
{{- $_ := set $computed "_APP_DB_HOST_DOCUMENTSDB" $docs.host }}
{{- $_ := set $computed "_APP_DB_PORT_DOCUMENTSDB" ($docs.port | toString) }}
{{- $_ := set $computed "_APP_DB_SCHEMA_DOCUMENTSDB" $docs.database }}
{{- $_ := set $computed "_APP_DB_USER_DOCUMENTSDB" $docs.username }}
{{- end }}
{{- $vectors := $v.vectorsDb }}
{{- $_ := set $computed "_APP_VECTORSDB" (get $enabled ($vectors.enabled | toString)) }}
{{- if $vectors.enabled }}
{{- $_ := set $computed "_APP_DB_ADAPTER_VECTORSDB" "postgresql" }}
{{- $_ := set $computed "_APP_DB_HOST_VECTORSDB" ($vectors.host | default $db.host) }}
{{- $_ := set $computed "_APP_DB_PORT_VECTORSDB" (ternary ($vectors.port | toString) ($db.port | toString) (not (empty $vectors.host))) }}
{{- $_ := set $computed "_APP_DB_SCHEMA_VECTORSDB" $vectors.database }}
{{- $_ := set $computed "_APP_DB_USER_VECTORSDB" $vectors.username }}
{{- end }}

{{- range $k, $val := $computed }}
{{- $_ := set $env $k ($val | toString) }}
{{- end }}
{{- range $k, $val := $v.config }}
{{- $_ := set $env $k ($val | toString) }}
{{- end }}
{{- toYaml $env }}
{{- end }}

{{/*
Name of the Secret holding chart-managed credentials.
*/}}
{{- define "appwrite.secretName" -}}
{{- include "appwrite.fullname" . }}
{{- end }}

{{/*
secretKeyRef for a credential that is either in a user-provided Secret or in
the chart-managed Secret.
Usage: include "appwrite.secretRef" (dict "root" $ "existingSecret" "x" "key" "k" "defaultKey" "dk")
*/}}
{{- define "appwrite.secretRef" -}}
secretKeyRef:
  {{- if .existingSecret }}
  name: {{ .existingSecret }}
  key: {{ .key }}
  {{- else }}
  name: {{ include "appwrite.secretName" .root }}
  key: {{ .defaultKey }}
  {{- end }}
{{- end }}

{{/*
Environment variables for every Appwrite container: credentials from Secrets
plus values that differ per component.
Usage: include "appwrite.env" (dict "root" $ "cpuNum" "1" "extra" (dict "_APP_WORKERS_NUM" "1"))
*/}}
{{- define "appwrite.env" -}}
{{- $root := .root }}
{{- $v := $root.Values }}
{{- $secrets := $v.appwrite.secrets }}
- name: _APP_OPENSSL_KEY_V1
  valueFrom:
    {{- include "appwrite.secretRef" (dict "root" $root "existingSecret" $secrets.existingSecret "key" $secrets.keys.opensslKey "defaultKey" "_APP_OPENSSL_KEY_V1") | nindent 4 }}
- name: _APP_NOTIFICATIONS_TRACKING_SECRET
  valueFrom:
    {{- include "appwrite.secretRef" (dict "root" $root "existingSecret" $secrets.existingSecret "key" $secrets.keys.trackingSecret "defaultKey" "_APP_NOTIFICATIONS_TRACKING_SECRET") | nindent 4 }}
- name: _APP_GEO_SECRET
  valueFrom:
    {{- include "appwrite.secretRef" (dict "root" $root "existingSecret" $secrets.existingSecret "key" $secrets.keys.geoSecret "defaultKey" "_APP_GEO_SECRET") | nindent 4 }}
{{- $db := include "appwrite.db" $root | fromYaml }}
{{- with $db.secret }}
- name: _APP_DB_PASS
  valueFrom:
    secretKeyRef:
      name: {{ .name }}
      key: {{ .key }}
{{- end }}
{{- with (include "appwrite.redis" $root | fromYaml).secret }}
- name: _APP_REDIS_PASS
  valueFrom:
    secretKeyRef:
      name: {{ .name }}
      key: {{ .key }}
{{- end }}
{{- $ch := include "appwrite.clickhouse" $root | fromYaml }}
{{- $credentials := $ch.username }}
{{- with $ch.secret }}
- name: _APP_USAGE_PASS
  valueFrom:
    secretKeyRef:
      name: {{ .name }}
      key: {{ .key }}
{{- $credentials = printf "%s:$(_APP_USAGE_PASS)" $ch.username }}
{{- end }}
{{- $dsn := printf "%s://%s@%s/%s" $ch.scheme $credentials $ch.address $ch.database }}
- name: _APP_CONNECTIONS_DB_USAGE
  value: {{ $dsn | quote }}
- name: _APP_CONNECTIONS_DB_EXECUTIONS
  value: {{ $dsn | quote }}
{{- range $name, $c := dict "DOCUMENTSDB" $v.appwrite.documentsDb "VECTORSDB" $v.appwrite.vectorsDb }}
{{- if $c.enabled }}
{{- with (include "appwrite.datastore.secret" (dict "root" $root "config" $c "chartKey" (printf "%s-password" (lower $name))) | fromYaml).secret }}
- name: _APP_DB_PASS_{{ $name }}
  valueFrom:
    secretKeyRef:
      name: {{ .name }}
      key: {{ .key }}
{{- end }}
{{- end }}
{{- end }}
{{- if or $v.appwrite.smtp.password $v.appwrite.smtp.existingSecret }}
- name: _APP_SMTP_PASSWORD
  valueFrom:
    {{- include "appwrite.secretRef" (dict "root" $root "existingSecret" $v.appwrite.smtp.existingSecret "key" $v.appwrite.smtp.passwordKey "defaultKey" "smtp-password") | nindent 4 }}
{{- end }}
- name: _APP_CPU_NUM
  value: {{ .cpuNum | quote }}
{{- range $k, $val := .extra }}
- name: {{ $k }}
  value: {{ $val | toString | quote }}
{{- end }}
{{- with $v.appwrite.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
envFrom for every Appwrite container.
*/}}
{{- define "appwrite.envFrom" -}}
- configMapRef:
    name: {{ include "appwrite.fullname" . }}-env
{{- if .Values.appwrite.secretConfig }}
- secretRef:
    name: {{ include "appwrite.fullname" . }}-env
{{- end }}
{{- with .Values.appwrite.extraEnvFrom }}
{{ toYaml . }}
{{- end }}
{{- end }}
