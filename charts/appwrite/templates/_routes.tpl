{{/*
Hostnames the main route serves: appwrite.domain and, when different, the console domain.
*/}}
{{- define "appwrite.routes.mainHosts" -}}
{{- $v := .Values.appwrite }}
{{- $hosts := list $v.domain }}
{{- if and $v.consoleDomain (ne $v.consoleDomain $v.domain) }}
{{- $hosts = append $hosts $v.consoleDomain }}
{{- end }}
{{- toYaml $hosts }}
{{- end }}

{{/*
Wildcard hostnames for function and site previews.
*/}}
{{- define "appwrite.routes.wildcardHosts" -}}
{{- $v := .Values.appwrite }}
{{- $functions := $v.functionsDomain | default (printf "functions.%s" $v.domain) }}
{{- $sites := $v.sitesDomain | default (printf "sites.%s" $v.domain) }}
{{- toYaml (list (printf "*.%s" $functions) (printf "*.%s" $sites)) }}
{{- end }}

{{/*
Path-based routes on the main hostnames, most specific first:
/v1/realtime to realtime, /v1 and /.well-known to the API, the rest to the
console (or the API when the console is disabled).
*/}}
{{- define "appwrite.routes.mainPaths" -}}
{{- $api := dict "service" "api" "port" .Values.api.service.port }}
{{- $paths := list }}
{{- if .Values.realtime.enabled }}
{{- $paths = append $paths (dict "path" "/v1/realtime" "service" "realtime" "port" .Values.realtime.service.port) }}
{{- end }}
{{- $paths = append $paths (merge (dict "path" "/v1") $api) }}
{{- $paths = append $paths (merge (dict "path" "/.well-known") $api) }}
{{- if .Values.console.enabled }}
{{- $paths = append $paths (dict "path" "/" "service" "console" "port" .Values.console.service.port) }}
{{- else }}
{{- $paths = append $paths (merge (dict "path" "/") $api) }}
{{- end }}
{{- toYaml $paths }}
{{- end }}
