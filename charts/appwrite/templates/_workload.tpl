{{/*
Deployment for a chart component.

Usage: include "appwrite.deployment" (dict
  "root" $                       root context
  "component" "api"              component name
  "role" "worker"                optional appwrite/role pod label (worker or task)
  "values" .Values.api           component values (resources, scheduling, probes, ...)
  "parent" .Values.workers       optional group values consulted before `defaults`
  "appwrite" true                runs the Appwrite image with the shared env
  "image" "repo:tag"             image reference (non-Appwrite components)
  "pullPolicy" "IfNotPresent"    image pull policy (non-Appwrite components)
  "command" (list ...)           container command
  "env" "<yaml list>"            extra container env (rendered YAML)
  "ports" (list ...)             container ports
  "probes" "<yaml>"              startupProbe/readinessProbe/livenessProbe (rendered YAML)
  "replicas" 1                   replica count; omitted when an HPA manages the Deployment
  "singleton" false              run exactly one pod and recreate it on update
  "spread" true                  default soft spread across nodes
  "storage" false                mount the /storage volume
  "certbot" false                mount writable certbot directories
  "initContainers" "<yaml list>" init containers (rendered YAML)
  "preStopSleepSeconds" 0        sleep before shutdown
  "annotations" (dict)           extra Deployment annotations
  "podAnnotations" (dict)        pod annotations, e.g. config checksums (non-Appwrite components)
  "serviceAccountName" ""        ServiceAccount other than the chart's shared one
  "automountServiceAccountToken" false   mount its token (only components that call the Kubernetes API)
)
*/}}
{{- define "appwrite.deployment" -}}
{{- $root := .root }}
{{- $v := .values }}
{{- $parent := .parent | default dict }}
{{- $name := include "appwrite.componentName" (dict "root" $root "component" .component) }}
{{- $podSecurityContext := $v.podSecurityContext | default $parent.podSecurityContext }}
{{- $containerSecurityContext := $v.containerSecurityContext | default $parent.containerSecurityContext }}
{{- if .appwrite }}
{{- $podSecurityContext = $podSecurityContext | default $root.Values.podSecurityContext }}
{{- $containerSecurityContext = $containerSecurityContext | default $root.Values.containerSecurityContext }}
{{- end }}
{{- $extraEnv := concat ($parent.extraEnv | default list) ($v.extraEnv | default list) }}
{{- $extraVolumes := concat ($parent.extraVolumes | default list) ($v.extraVolumes | default list) }}
{{- $extraVolumeMounts := concat ($parent.extraVolumeMounts | default list) ($v.extraVolumeMounts | default list) }}
{{- $podLabels := dict }}
{{- if .appwrite }}
{{- /* Selects the pods NetworkPolicies let through to the datastores. */}}
{{- $_ := set $podLabels "appwrite/datastore-client" "true" }}
{{- end }}
{{- if .storage }}
{{- $_ := set $podLabels "appwrite/storage" "shared" }}
{{- end }}
{{- with .role }}
{{- $_ := set $podLabels "appwrite/role" . }}
{{- end }}
{{- $podAnnotations := .podAnnotations | default dict }}
{{- if .appwrite }}
{{- $podAnnotations = include "appwrite.pod.checksums" $root | fromYaml }}
{{- end }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $name }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- include "appwrite.componentLabels" (dict "root" $root "component" .component) | nindent 4 }}
  {{- with include "appwrite.annotations" (dict "root" $root "annotations" (.annotations | default dict)) | trim }}{{ . | nindent 2 }}{{ end }}
spec:
  {{- if .singleton }}
  replicas: 1
  strategy:
    type: Recreate
  {{- else }}
  {{- if not (kindIs "invalid" .replicas) }}
  replicas: {{ .replicas }}
  {{- end }}
  {{- with $v.updateStrategy }}
  strategy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- end }}
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      {{- include "appwrite.componentSelectorLabels" (dict "root" $root "component" .component) | nindent 6 }}
  template:
    metadata:
      {{- include "appwrite.pod.metadata" (dict "root" $root "values" $v "parent" $parent "component" .component "labels" $podLabels "annotations" $podAnnotations) | trim | nindent 6 }}
    spec:
      serviceAccountName: {{ .serviceAccountName | default (include "appwrite.serviceAccountName" $root) }}
      automountServiceAccountToken: {{ .automountServiceAccountToken | default false }}
      enableServiceLinks: false
      {{- with include "appwrite.imagePullSecrets" $root | trim }}{{ . | nindent 6 }}{{ end }}
      {{- with $podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      terminationGracePeriodSeconds: {{ $v.terminationGracePeriodSeconds | default $parent.terminationGracePeriodSeconds | default 30 }}
      {{- with include "appwrite.pod.scheduling" (dict "root" $root "values" $v "parent" $parent "component" .component "spread" .spread "storage" .storage) | trim }}{{ . | nindent 6 }}{{ end }}
      {{- if or .initContainers $v.extraInitContainers }}
      initContainers:
        {{- with .initContainers }}
        {{- . | trim | nindent 8 }}
        {{- end }}
        {{- with $v.extraInitContainers }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- end }}
      containers:
        - name: {{ .component }}
          {{- if .appwrite }}
          image: {{ include "appwrite.appwriteImage" $root }}
          imagePullPolicy: {{ $root.Values.image.pullPolicy }}
          {{- else }}
          image: {{ .image }}
          imagePullPolicy: {{ .pullPolicy }}
          {{- end }}
          {{- with .command }}
          command:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .ports }}
          ports:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- if .appwrite }}
          envFrom:
            {{- include "appwrite.envFrom" $root | nindent 12 }}
          {{- end }}
          {{- if or .env $extraEnv }}
          env:
            {{- with .env }}
            {{- . | trim | nindent 12 }}
            {{- end }}
            {{- with $extraEnv }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          {{- end }}
          {{- with .probes }}
          {{- . | trim | nindent 10 }}
          {{- end }}
          {{- if .preStopSleepSeconds }}
          lifecycle:
            preStop:
              exec:
                command: ["sleep", "{{ .preStopSleepSeconds }}"]
          {{- end }}
          {{- with $containerSecurityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $v.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- if or .appwrite $extraVolumeMounts .volumeMounts }}
          volumeMounts:
            {{- if .appwrite }}
            {{- include "appwrite.volumeMounts" (dict "root" $root "storage" .storage "certbot" .certbot) | nindent 12 }}
            {{- end }}
            {{- with .volumeMounts }}
            {{- . | nindent 12 }}
            {{- end }}
            {{- with $extraVolumeMounts }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          {{- end }}
        {{- with $v.extraContainers }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- if or .appwrite $extraVolumes .volumes }}
      volumes:
        {{- if .appwrite }}
        {{- include "appwrite.volumes" (dict "root" $root "storage" .storage "certbot" .certbot) | nindent 8 }}
        {{- end }}
        {{- with .volumes }}
        {{- . | nindent 8 }}
        {{- end }}
        {{- with $extraVolumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- end }}
{{- end }}

{{/*
ClusterIP (or other type) Service for a component.
Usage: include "appwrite.service" (dict "root" $ "component" "api" "service" .Values.api.service "ports" (list (dict "name" "http" "port" 80 "targetPort" "http")))
*/}}
{{- define "appwrite.service" -}}
{{- $name := include "appwrite.componentName" (dict "root" .root "component" .component) }}
apiVersion: v1
kind: Service
metadata:
  name: {{ if .headless }}{{ $name }}-headless{{ else }}{{ $name }}{{ end }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "appwrite.componentLabels" (dict "root" .root "component" .component) | nindent 4 }}
  {{- with include "appwrite.annotations" (dict "root" .root "annotations" (.service.annotations | default dict)) | trim }}{{ . | nindent 2 }}{{ end }}
spec:
  type: {{ .service.type | default "ClusterIP" }}
  {{- if .headless }}
  clusterIP: None
  publishNotReadyAddresses: true
  {{- end }}
  ports:
    {{- range .ports }}
    - name: {{ .name }}
      port: {{ .port }}
      targetPort: {{ .targetPort }}
      protocol: {{ .protocol | default "TCP" }}
      {{- if .appProtocol }}
      appProtocol: {{ .appProtocol }}
      {{- end }}
    {{- end }}
  selector:
    {{- include "appwrite.componentSelectorLabels" (dict "root" .root "component" .component) | nindent 4 }}
{{- end }}

{{/*
HorizontalPodAutoscaler for a component.
Usage: include "appwrite.hpa" (dict "root" $ "component" "api" "autoscaling" .Values.api.autoscaling)
*/}}
{{- define "appwrite.hpa" -}}
{{- $a := .autoscaling }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "appwrite.componentName" (dict "root" .root "component" .component) }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "appwrite.componentLabels" (dict "root" .root "component" .component) | nindent 4 }}
  {{- with include "appwrite.annotations" (dict "root" .root) | trim }}{{ . | nindent 2 }}{{ end }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "appwrite.componentName" (dict "root" .root "component" .component) }}
  minReplicas: {{ $a.minReplicas }}
  maxReplicas: {{ $a.maxReplicas }}
  metrics:
    {{- if $a.targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ $a.targetCPUUtilizationPercentage }}
    {{- end }}
    {{- if $a.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ $a.targetMemoryUtilizationPercentage }}
    {{- end }}
  {{- with $a.behavior }}
  behavior:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}

{{/*
PodDisruptionBudget for a component. Only rendered when more than one pod
can run; a PDB on a single replica would block node drains.
Usage: include "appwrite.pdb" (dict "root" $ "component" "api" "pdb" .Values.api.pdb "replicas" 1 "autoscaling" .Values.api.autoscaling)
*/}}
{{- define "appwrite.pdb" -}}
{{- $multi := or (gt (int .replicas) 1) (and .autoscaling .autoscaling.enabled (gt (int .autoscaling.minReplicas) 1)) }}
{{- if and .pdb.enabled $multi }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "appwrite.componentName" (dict "root" .root "component" .component) }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "appwrite.componentLabels" (dict "root" .root "component" .component) | nindent 4 }}
  {{- with include "appwrite.annotations" (dict "root" .root) | trim }}{{ . | nindent 2 }}{{ end }}
spec:
  {{- if not (kindIs "string" .pdb.minAvailable) }}
  minAvailable: {{ .pdb.minAvailable }}
  {{- else if .pdb.minAvailable }}
  minAvailable: {{ .pdb.minAvailable }}
  {{- else }}
  maxUnavailable: {{ .pdb.maxUnavailable }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "appwrite.componentSelectorLabels" (dict "root" .root "component" .component) | nindent 6 }}
{{- end }}
{{- end }}

{{/*
startupProbe/readinessProbe/livenessProbe for a component from its probe
settings and a handler.
Usage: include "appwrite.probes" (dict "values" .Values.api "handler" (dict "httpGet" (dict ...)))
*/}}
{{- define "appwrite.probes" -}}
{{- range $probe := list "startupProbe" "readinessProbe" "livenessProbe" }}
{{- $settings := get $.values $probe | default dict }}
{{- if $settings.enabled }}
{{ $probe }}:
  {{- toYaml $.handler | nindent 2 }}
  {{- toYaml (omit $settings "enabled") | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
