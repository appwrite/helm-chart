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
Labels for a component's pod template. Leaves out helm.sh/chart and
app.kubernetes.io/version, so a chart bump doesn't restart pods (the
datastores) or change an immutable Job template.
Usage: include "appwrite.podLabels" (dict "root" $ "component" "api")
*/}}
{{- define "appwrite.podLabels" -}}
{{ include "appwrite.componentSelectorLabels" . }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/part-of: appwrite
{{- with .root.Values.commonLabels }}
{{ toYaml . }}
{{- end }}
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
  {{- if kindIs "map" . }}
  - name: {{ .name }}
  {{- else }}
  - name: {{ . }}
  {{- end }}
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
Internal hostname of the API Service, resolvable from any namespace. It is
_APP_MIGRATION_HOST, which Appwrite treats like localhost (exempt from
force-HTTPS and router protection), so it is also the Host header of probes
and of in-cluster callers such as build Jobs.
*/}}
{{- define "appwrite.api.internalHost" -}}
{{- printf "%s.%s.svc" (include "appwrite.api.host" .) .Release.Namespace }}
{{- end }}

{{/*
In-cluster URL of the API Service, reachable from other namespaces.
*/}}
{{- define "appwrite.api.url" -}}
{{- $port := int .Values.api.service.port }}
{{- printf "http://%s%s" (include "appwrite.api.internalHost" .) (ternary "" (printf ":%d" $port) (eq $port 80)) }}
{{- end }}

{{/*
Most Appwrite pods that can run at once (autoscalers at maxReplicas). Each
opens its own database pool, sized _APP_CONNECTIONS_MAX / _APP_POOL_CLIENTS.
*/}}
{{- define "appwrite.pods.max" -}}
{{- $n := 0 }}
{{- $scaled := list .Values.api }}
{{- if .Values.realtime.enabled }}{{ $scaled = append $scaled .Values.realtime }}{{ end }}
{{- range (include "appwrite.workers.deployments" . | fromYamlArray) }}
{{- $scaled = append $scaled .values }}
{{- end }}
{{- range $scaled }}
{{- if and .autoscaling .autoscaling.enabled }}
{{- $n = add $n (.autoscaling.maxReplicas | int) }}
{{- else }}
{{- $n = add $n (.replicaCount | default 0 | int) }}
{{- end }}
{{- end }}
{{- if .Values.mqtt.enabled }}{{ $n = add $n (.Values.mqtt.replicaCount | int) }}{{ end }}
{{- $t := .Values.tasks }}
{{- if $t.scheduler.enabled }}{{ $n = add $n (ternary 4 1 (eq $t.scheduler.mode "separate")) }}{{ end }}
{{- if $t.maintenance.enabled }}{{ $n = add $n 1 }}{{ end }}
{{- if $t.interval.enabled }}{{ $n = add $n 1 }}{{ end }}
{{- $n }}
{{- end }}

{{/*
First value in a list that is set (not null or missing); unlike `default`,
0 and false count as set.
Usage: include "appwrite.firstSet" (list $v.x $parent.x 30)
*/}}
{{- define "appwrite.firstSet" -}}
{{- $out := "" }}
{{- $found := false }}
{{- range . }}
{{- if and (not $found) (not (kindIs "invalid" .)) }}
{{- $out = . }}
{{- $found = true }}
{{- end }}
{{- end }}
{{- $out }}
{{- end }}

{{/*
Name of a datastore's headless Service, kept within 63 characters.
Usage: include "appwrite.headlessName" (dict "root" $ "component" "postgresql")
*/}}
{{- define "appwrite.headlessName" -}}
{{- printf "%s-headless" (include "appwrite.componentName" . | trunc 54 | trimSuffix "-") }}
{{- end }}

{{/*
Maps layered key by key, first layer winning; a key set in an earlier layer
(even to false or 0) is kept. Returns YAML.
Usage: include "appwrite.overlay" (list $component $group $global) | fromYaml
*/}}
{{- define "appwrite.overlay" -}}
{{- $out := dict }}
{{- range . }}
{{- range $k, $val := . | default dict }}
{{- if not (hasKey $out $k) }}{{ $_ := set $out $k $val }}{{ end }}
{{- end }}
{{- end }}
{{- toYaml $out }}
{{- end }}
