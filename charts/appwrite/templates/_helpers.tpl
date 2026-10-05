{{/*
Chart name, truncated to 63 characters (DNS-1123 label limit).
*/}}
{{- define "appwrite.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name. Truncated to 63 characters; if the release name
already contains the chart name it is used as-is.
*/}}
{{- define "appwrite.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Name of a component's resources: <fullname>-<component>.
Usage: include "appwrite.componentName" (dict "root" $ "component" "api")
*/}}
{{- define "appwrite.componentName" -}}
{{- printf "%s-%s" (include "appwrite.fullname" .root) .component | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Chart label value: name-version, with "+" replaced for label safety.
*/}}
{{- define "appwrite.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels. Pass the root context.
*/}}
{{- define "appwrite.labels" -}}
helm.sh/chart: {{ include "appwrite.chart" . }}
{{ include "appwrite.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: appwrite
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels. Pass the root context.
*/}}
{{- define "appwrite.selectorLabels" -}}
app.kubernetes.io/name: {{ include "appwrite.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Labels for a component.
Usage: include "appwrite.componentLabels" (dict "root" $ "component" "api")
*/}}
{{- define "appwrite.componentLabels" -}}
{{ include "appwrite.labels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Selector labels for a component.
Usage: include "appwrite.componentSelectorLabels" (dict "root" $ "component" "api")
*/}}
{{- define "appwrite.componentSelectorLabels" -}}
{{ include "appwrite.selectorLabels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Resource metadata annotations: commonAnnotations merged with extra annotations.
Usage: include "appwrite.annotations" (dict "root" $ "annotations" .Values.x.annotations)
Renders nothing when there are no annotations.
*/}}
{{- define "appwrite.annotations" -}}
{{- $annotations := merge (dict) (.annotations | default dict) (.root.Values.commonAnnotations | default dict) }}
{{- with $annotations }}
annotations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Name of the ServiceAccount to use.
*/}}
{{- define "appwrite.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "appwrite.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Full image reference. global.imageRegistry replaces the image's registry.
The tag defaults to the chart appVersion only for the Appwrite image.
Usage: include "appwrite.image" (dict "root" $ "image" .Values.image "defaultTag" $.Chart.AppVersion)
*/}}
{{- define "appwrite.image" -}}
{{- $registry := .root.Values.global.imageRegistry | default .image.registry }}
{{- $tag := .image.tag | default .defaultTag | toString }}
{{- $ref := .image.repository }}
{{- if $registry }}
{{- $ref = printf "%s/%s" $registry $ref }}
{{- end }}
{{- if $tag }}
{{- $ref = printf "%s:%s" $ref $tag }}
{{- end }}
{{- if .image.digest }}
{{- $ref = printf "%s@%s" $ref .image.digest }}
{{- end }}
{{- $ref }}
{{- end }}

{{/*
Appwrite image reference.
*/}}
{{- define "appwrite.appwriteImage" -}}
{{- include "appwrite.image" (dict "root" . "image" .Values.image "defaultTag" .Chart.AppVersion) }}
{{- end }}

{{/*
imagePullSecrets block for a pod spec.
*/}}
{{- define "appwrite.imagePullSecrets" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
  {{- range . }}
  - name: {{ . }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Value of _APP_CPU_NUM for a component: the explicit cpuNum, else the CPU
limit, else the CPU request, rounded up; at least 1. Appwrite would otherwise
size worker and connection pools for every CPU on the node.
Usage: include "appwrite.cpuNum" (dict "cpuNum" .cpuNum "resources" .resources)
*/}}
{{- define "appwrite.cpuNum" -}}
{{- $cpu := "" }}
{{- if not (empty .cpuNum) }}
{{- $cpu = .cpuNum | toString }}
{{- else if and .resources .resources.limits .resources.limits.cpu }}
{{- $cpu = .resources.limits.cpu | toString }}
{{- else if and .resources .resources.requests .resources.requests.cpu }}
{{- $cpu = .resources.requests.cpu | toString }}
{{- end }}
{{- $n := 1 }}
{{- if hasSuffix "m" $cpu }}
{{- $n = divf (trimSuffix "m" $cpu | float64) 1000 | ceil | int }}
{{- else if $cpu }}
{{- $n = $cpu | float64 | ceil | int }}
{{- end }}
{{- max $n 1 }}
{{- end }}

{{/*
Name of a Service for a component (also its DNS name inside the namespace).
*/}}
{{- define "appwrite.api.host" -}}
{{- include "appwrite.componentName" (dict "root" . "component" "api") }}
{{- end }}

{{/*
Whether the Appwrite /storage volume is a ReadWriteOnce claim whose pods
must share a node. Returns "true" or "".
*/}}
{{- define "appwrite.storage.colocate" -}}
{{- $p := .Values.persistence }}
{{- if and $p.enabled $p.colocateReadWriteOnce (has "ReadWriteOnce" $p.accessModes) }}true{{ end }}
{{- end }}

{{/*
Environment variable value as a string. Whole numbers from YAML (which Helm
reads as floats) render as integers, so 30000000 doesn't become 3e+07.
*/}}
{{- define "appwrite.envValue" -}}
{{- if and (kindIs "float64" .) (eq (floor .) .) }}
{{- . | int64 | toString }}
{{- else }}
{{- . | toString }}
{{- end }}
{{- end }}

{{/*
"true" when builds run in the cluster: compute is on and the chart runs the
orchestrator.
*/}}
{{- define "appwrite.builds.inCluster" -}}
{{- if and .Values.compute.enabled (eq .Values.compute.orchestrator.mode "cluster") }}true{{ end }}
{{- end }}

{{/*
Namespace build Jobs run in.
*/}}
{{- define "appwrite.builds.namespace" -}}
{{- .Values.compute.builds.namespace | default (printf "%s-builds" .Release.Namespace) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
In-cluster URL of the API Service, reachable from other namespaces.
*/}}
{{- define "appwrite.api.url" -}}
{{- $port := int .Values.api.service.port }}
{{- printf "http://%s.%s.svc%s" (include "appwrite.api.host" .) .Release.Namespace (ternary "" (printf ":%d" $port) (eq $port 80)) }}
{{- end }}
