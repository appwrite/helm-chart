{{/*
Environment shared by every Appwrite pod, as a dict of strings. Rendered into
the env ConfigMap. Precedence, lowest first:
  1. files/env-defaults.yaml (what the Docker installer writes to .env)
  2. values computed by the chart (domains, internal service URLs, ...)
  3. appwrite.config
appwrite.config and secretConfig also replace the variables the chart sets
on each container (see appwrite.env).
*/}}
{{- define "appwrite.env.config" -}}
{{- $root := . }}
{{- $v := .Values.appwrite }}
{{- $fullname := include "appwrite.fullname" . }}
{{- $domain := $v.domain | default "localhost" }}
{{- $enabled := dict "true" "enabled" "false" "disabled" }}
{{- $env := .Files.Get "files/env-defaults.yaml" | fromYaml | default dict }}
{{- $apiHost := include "appwrite.api.internalHost" . }}

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
  "_APP_WORKER_PER_CORE" $v.workerPerCore
  "_APP_CONSOLE_WHITELIST_ROOT" (get $enabled ($v.console.whitelistRoot | toString))
  "_APP_CONSOLE_WHITELIST_EMAILS" (join "," $v.console.whitelistEmails)
  "_APP_CONSOLE_WHITELIST_IPS" (join "," $v.console.whitelistIPs)
  "_APP_SYSTEM_EMAIL_NAME" $v.system.emailName
  "_APP_SYSTEM_EMAIL_ADDRESS" ($v.system.emailAddress | default (printf "noreply@%s" $domain))
  "_APP_EMAIL_SECURITY" $v.system.securityEmailAddress
  "_APP_CONNECTIONS_MAX" $v.database.connectionsMax
  "_APP_POOL_CLIENTS" $v.database.poolClients
  "_APP_SMTP_HOST" $v.smtp.host
  "_APP_SMTP_PORT" $v.smtp.port
  "_APP_SMTP_SECURE" $v.smtp.secure
  "_APP_SMTP_USERNAME" $v.smtp.username
  "_APP_MIGRATION_HOST" $apiHost
  "_APP_WORKER_SCREENSHOTS_ROUTER" (printf "http://%s" $apiHost)
  "_APP_JOBS_ENDPOINT" (printf "http://%s" $apiHost)
  "_APP_GEO_ENDPOINT" (ternary (printf "http://%s/v1" (include "appwrite.componentName" (dict "root" . "component" "geo"))) "" .Values.geo.enabled)
  "_APP_AUTOGRAVITY_HOST" (ternary (printf "http://%s:8080" (include "appwrite.componentName" (dict "root" . "component" "autogravity"))) "" .Values.autogravity.enabled)
  "_APP_EMBEDDING" (get $enabled (.Values.embedding.enabled | toString))
  "_APP_EMBEDDING_ENDPOINT" (printf "http://%s:3000/embed" (include "appwrite.componentName" (dict "root" . "component" "embedding")))
}}
{{- if .Values.browser.enabled }}
{{- $_ := set $computed "_APP_BROWSER_HOST" (printf "http://%s:3000/v1" (include "appwrite.componentName" (dict "root" . "component" "browser"))) }}
{{- end }}

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

{{- /* Storage */}}
{{- $storage := $v.storage }}
{{- $_ := set $computed "_APP_STORAGE_DEVICE" $storage.device }}
{{- $_ := set $computed "_APP_STORAGE_LIMIT" $storage.limit }}
{{- $_ := set $computed "_APP_STORAGE_PREVIEW_LIMIT" $storage.previewLimit }}
{{- if eq $storage.device "s3" }}
{{- $_ := set $computed "_APP_STORAGE_S3_ENDPOINT" $storage.s3.endpoint }}
{{- $_ := set $computed "_APP_STORAGE_S3_REGION" $storage.s3.region }}
{{- $_ := set $computed "_APP_STORAGE_S3_BUCKET" $storage.s3.bucket }}
{{- end }}

{{- /* Compute plane (Functions and Sites): the orchestrator runs builds as Jobs, the executor runs executions; build Jobs call back to the API Service */}}
{{- $compute := .Values.compute }}
{{- if $compute.enabled }}
{{- $_ := set $computed "_APP_EXECUTOR_HOST" (include "appwrite.executor.url" .) }}
{{- $_ := set $computed "_APP_JOBS_HOST" (printf "http://%s:8080" (include "appwrite.componentName" (dict "root" . "component" "orchestrator"))) }}
{{- $_ := set $computed "_APP_JOBS_ENDPOINT" (include "appwrite.api.url" .) }}
{{- end }}
{{- with $compute.functionsRuntimes }}
{{- $_ := set $computed "_APP_FUNCTIONS_RUNTIMES" (join "," .) }}
{{- end }}
{{- with $compute.sitesRuntimes }}
{{- $_ := set $computed "_APP_SITES_RUNTIMES" (join "," .) }}
{{- end }}

{{- range $k, $val := $computed }}
{{- $_ := set $env $k (include "appwrite.envValue" $val) }}
{{- end }}
{{- range $k, $val := $v.config }}
{{- $_ := set $env $k (include "appwrite.envValue" $val) }}
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
{{- /* Container env wins over envFrom: leave out what appwrite.config or secretConfig sets. */}}
{{- $overrides := merge (dict) ($v.appwrite.config | default dict) ($v.appwrite.secretConfig | default dict) }}
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
{{- /* Appwrite ignores the scheme and only uses TLS with secure=true. */}}
{{- if eq $ch.scheme "https" }}
{{- $dsn = printf "%s?secure=true" $dsn }}
{{- end }}
{{- range $name := list "_APP_CONNECTIONS_DB_USAGE" "_APP_CONNECTIONS_DB_EXECUTIONS" }}
{{- if not (hasKey $overrides $name) }}
- name: {{ $name }}
  value: {{ $dsn | quote }}
{{- end }}
{{- end }}
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
{{- $s3 := $v.appwrite.storage.s3 }}
{{- if and (eq $v.appwrite.storage.device "s3") (or $s3.existingSecret $s3.accessKey) }}
- name: _APP_STORAGE_S3_ACCESS_KEY
  valueFrom:
    {{- include "appwrite.secretRef" (dict "root" $root "existingSecret" $s3.existingSecret "key" $s3.accessKeyKey "defaultKey" "s3-access-key") | nindent 4 }}
- name: _APP_STORAGE_S3_SECRET
  valueFrom:
    {{- include "appwrite.secretRef" (dict "root" $root "existingSecret" $s3.existingSecret "key" $s3.secretKeyKey "defaultKey" "s3-secret-key") | nindent 4 }}
{{- end }}
{{- $cs := $v.compute.secrets }}
{{- if $v.compute.enabled }}
- name: _APP_EXECUTOR_SECRET
  valueFrom:
    {{- include "appwrite.secretRef" (dict "root" $root "existingSecret" $cs.existingSecret "key" $cs.executorSecretKey "defaultKey" "executor-secret") | nindent 4 }}
- name: _APP_JOBS_SECRET
  valueFrom:
    {{- include "appwrite.secretRef" (dict "root" $root "existingSecret" $cs.existingSecret "key" $cs.orchestratorSecretKey "defaultKey" "orchestrator-secret") | nindent 4 }}
{{- end }}
{{- if $v.assistant.enabled }}
{{- /* The console shows the assistant when Appwrite has the key. */}}
- name: _APP_ASSISTANT_OPENAI_API_KEY
  valueFrom:
    {{- include "appwrite.secretRef" (dict "root" $root "existingSecret" $v.assistant.existingSecret "key" $v.assistant.secretKey "defaultKey" "openai-api-key") | nindent 4 }}
{{- end }}
{{- if or $v.appwrite.smtp.password $v.appwrite.smtp.existingSecret }}
- name: _APP_SMTP_PASSWORD
  valueFrom:
    {{- include "appwrite.secretRef" (dict "root" $root "existingSecret" $v.appwrite.smtp.existingSecret "key" $v.appwrite.smtp.passwordKey "defaultKey" "smtp-password") | nindent 4 }}
{{- end }}
{{- range $k, $val := merge (dict "_APP_CPU_NUM" .cpuNum) .extra }}
{{- if not (hasKey $overrides $k) }}
- name: {{ $k }}
  value: {{ include "appwrite.envValue" $val | quote }}
{{- end }}
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
