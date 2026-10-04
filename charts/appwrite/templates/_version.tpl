{{/*
Appwrite version the chart deploys: the image tag, or the chart appVersion.
*/}}
{{- define "appwrite.version" -}}
{{- .Values.image.tag | default .Chart.AppVersion | toString }}
{{- end }}

{{/*
Appwrite version currently running, read from the API Deployment's
appwrite/version annotation. Empty on install, or when the cluster can't be
read (helm template).
*/}}
{{- define "appwrite.installedVersion" -}}
{{- $api := lookup "apps/v1" "Deployment" .Release.Namespace (include "appwrite.api.host" .) }}
{{- if $api }}
{{- dig "metadata" "annotations" "appwrite/version" "" $api }}
{{- end }}
{{- end }}

{{/*
"true" when an upgrade changes the Appwrite version, or when that can't be
determined.
*/}}
{{- define "appwrite.versionChanged" -}}
{{- $installed := include "appwrite.installedVersion" . }}
{{- if or (not $installed) (ne $installed (include "appwrite.version" .)) }}true{{ end }}
{{- end }}
