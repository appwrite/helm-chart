{{/*
Data of the chart-managed Secret, as YAML (key: base64 value).

Generated values are created once and then reused: the existing Secret is
read back with `lookup` on every upgrade. Without cluster access (`helm
template`, Argo CD) lookup returns nothing, so set
`appwrite.secrets.generate: false` there and provide existing Secrets.
*/}}
{{- define "appwrite.secret.data" -}}
{{- if not (hasKey .Values "__secretData") }}
{{- $existing := (lookup "v1" "Secret" .Release.Namespace (include "appwrite.secretName" .)).data | default dict }}
{{- $data := dict }}
{{- $s := .Values.appwrite.secrets }}
{{- if not $s.existingSecret }}
{{- range $key, $explicit := dict "_APP_OPENSSL_KEY_V1" $s.opensslKey "_APP_NOTIFICATIONS_TRACKING_SECRET" $s.trackingSecret "_APP_GEO_SECRET" $s.geoSecret }}
{{- $_ := set $data $key (include "appwrite.secret.value" (dict "root" $ "existing" $existing "key" $key "explicit" $explicit)) }}
{{- end }}
{{- end }}
{{- $stores := list
  (list .Values.postgresql.enabled .Values.postgresql.auth "postgres-password")
  (list (and .Values.redis.enabled .Values.redis.auth.enabled) .Values.redis.auth "redis-password")
  (list .Values.clickhouse.enabled .Values.clickhouse.auth "clickhouse-password") }}
{{- range $stores }}
{{- $on := index . 0 }}
{{- $auth := index . 1 }}
{{- $key := index . 2 }}
{{- if and $on (not $auth.existingSecret) }}
{{- $_ := set $data $key (include "appwrite.secret.value" (dict "root" $ "existing" $existing "key" $key "explicit" $auth.password)) }}
{{- end }}
{{- end }}
{{- /* Inline passwords of external services, stored so pods can reference them. */}}
{{- $external := list
  (list (not .Values.postgresql.enabled) .Values.externalDatabase "db-password")
  (list (not .Values.redis.enabled) .Values.externalRedis "redis-password")
  (list (not .Values.clickhouse.enabled) .Values.externalClickhouse "clickhouse-password")
  (list .Values.appwrite.documentsDb.enabled .Values.appwrite.documentsDb "documentsdb-password")
  (list .Values.appwrite.vectorsDb.enabled .Values.appwrite.vectorsDb "vectorsdb-password") }}
{{- range $external }}
{{- $on := index . 0 }}
{{- $c := index . 1 }}
{{- if and $on $c.password (not $c.existingSecret) }}
{{- $_ := set $data (index . 2) ($c.password | toString | b64enc) }}
{{- end }}
{{- end }}
{{- with .Values.appwrite.smtp }}
{{- if and .password (not .existingSecret) }}
{{- $_ := set $data "smtp-password" (.password | b64enc) }}
{{- end }}
{{- end }}
{{- /* Cache the result: random values must be identical everywhere this is included. */}}
{{- $_ := set .Values "__secretData" $data }}
{{- end }}
{{- toYaml (get .Values "__secretData") }}
{{- end }}

{{/*
Base64 value for one generated credential: the explicit value, else the
value already stored in the cluster, else a new random value.
*/}}
{{- define "appwrite.secret.value" -}}
{{- $current := get .existing .key }}
{{- if .explicit }}
{{- if and $current (eq .key "_APP_OPENSSL_KEY_V1") (ne (b64dec $current) .explicit) (not .root.Values.appwrite.secrets.allowKeyRotation) }}
{{- fail "appwrite.secrets.opensslKey differs from the key stored in the cluster. Changing _APP_OPENSSL_KEY_V1 makes encrypted data unreadable. Set appwrite.secrets.allowKeyRotation=true only if you know what you are doing." }}
{{- end }}
{{- .explicit | toString | b64enc }}
{{- else if $current }}
{{- $current }}
{{- else if not .root.Values.appwrite.secrets.generate }}
{{- fail (printf "No value for %s: provide it explicitly or through an existing Secret (appwrite.secrets.generate is false)." .key) }}
{{- else if and .root.Release.IsUpgrade (eq .key "_APP_OPENSSL_KEY_V1") }}
{{- fail (printf "Refusing to generate a new _APP_OPENSSL_KEY_V1 during an upgrade: Secret %s/%s was not found. Restore it, or set appwrite.secrets.existingSecret or appwrite.secrets.opensslKey. With --dry-run, use --dry-run=server so the existing Secret can be read." .root.Release.Namespace (include "appwrite.secretName" .root)) }}
{{- else }}
{{- randAlphaNum 48 | b64enc }}
{{- end }}
{{- end }}
