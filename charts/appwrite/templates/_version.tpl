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

{{/*
Name of the post-upgrade migration hook Job.
*/}}
{{- define "appwrite.migrateHookName" -}}
{{- printf "%s-migrate" (include "appwrite.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
"true" when the previous hook migration didn't finish. Helm deletes the hook
Job when it succeeds, so a Job still in the cluster failed or outlived the
hook timeout. The API's appwrite/version annotation has already moved on by
then, so without this check the next upgrade would skip the migration.
*/}}
{{- define "appwrite.migrationFailed" -}}
{{- if lookup "batch/v1" "Job" .Release.Namespace (include "appwrite.migrateHookName" .) }}true{{ end }}
{{- end }}
