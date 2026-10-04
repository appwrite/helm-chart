{{/*
Single-replica StatefulSet for a built-in datastore.

Usage: include "appwrite.datastore" (dict
  "root" $
  "component" "postgresql"
  "values" .Values.postgresql
  "command" (list ...)          optional
  "args" (list ...)             optional
  "env" "<yaml list>"
  "ports" (list ...)
  "probes" "<yaml>"
  "dataPath" "/var/lib/postgresql"
  "volumeMounts" "<yaml list>"  extra mounts
  "volumes" "<yaml list>"       extra volumes
  "annotations" (dict)          extra pod annotations (config checksums)
)
*/}}
{{- define "appwrite.datastore" -}}
{{- $root := .root }}
{{- $v := .values }}
{{- $name := include "appwrite.componentName" (dict "root" $root "component" .component) }}
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ $name }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- include "appwrite.componentLabels" (dict "root" $root "component" .component) | nindent 4 }}
  {{- with include "appwrite.annotations" (dict "root" $root) | trim }}{{ . | nindent 2 }}{{ end }}
spec:
  replicas: 1
  serviceName: {{ $name }}-headless
  podManagementPolicy: OrderedReady
  updateStrategy:
    type: RollingUpdate
  selector:
    matchLabels:
      {{- include "appwrite.componentSelectorLabels" (dict "root" $root "component" .component) | nindent 6 }}
  template:
    metadata:
      {{- include "appwrite.pod.metadata" (dict "root" $root "values" $v "component" .component "annotations" (.annotations | default dict)) | trim | nindent 6 }}
    spec:
      serviceAccountName: {{ include "appwrite.serviceAccountName" $root }}
      automountServiceAccountToken: false
      enableServiceLinks: false
      {{- with include "appwrite.imagePullSecrets" $root | trim }}{{ . | nindent 6 }}{{ end }}
      {{- with $v.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      terminationGracePeriodSeconds: {{ $v.terminationGracePeriodSeconds | default 60 }}
      {{- with include "appwrite.pod.scheduling" (dict "root" $root "values" $v "component" .component) | trim }}{{ . | nindent 6 }}{{ end }}
      containers:
        - name: {{ .component }}
          image: {{ include "appwrite.image" (dict "root" $root "image" $v.image) }}
          imagePullPolicy: {{ $v.image.pullPolicy }}
          {{- with .command }}
          command:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .args }}
          args:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .env }}
          env:
            {{- . | nindent 12 }}
          {{- end }}
          ports:
            {{- toYaml .ports | nindent 12 }}
          {{- with .probes }}
          {{- . | trim | nindent 10 }}
          {{- end }}
          {{- with $v.containerSecurityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $v.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          volumeMounts:
            - name: data
              mountPath: {{ .dataPath }}
            - name: tmp
              mountPath: /tmp
            {{- with .volumeMounts }}
            {{- . | nindent 12 }}
            {{- end }}
      volumes:
        - name: tmp
          emptyDir: {}
        {{- if not $v.persistence.enabled }}
        - name: data
          emptyDir: {}
        {{- end }}
        {{- with .volumes }}
        {{- . | nindent 8 }}
        {{- end }}
  {{- if $v.persistence.enabled }}
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Retain
    whenScaled: Retain
  volumeClaimTemplates:
    - metadata:
        name: data
        labels:
          {{- include "appwrite.componentSelectorLabels" (dict "root" $root "component" .component) | nindent 10 }}
        {{- with $v.persistence.annotations }}
        annotations:
          {{- toYaml . | nindent 10 }}
        {{- end }}
      spec:
        accessModes:
          {{- toYaml $v.persistence.accessModes | nindent 10 }}
        {{- with ($v.persistence.storageClass | default $root.Values.global.storageClass) }}
        storageClassName: {{ if eq . "-" }}""{{ else }}{{ . }}{{ end }}
        {{- end }}
        resources:
          requests:
            storage: {{ $v.persistence.size }}
  {{- end }}
{{- end }}

{{/*
Probes for a datastore with a fixed handler.
*/}}
{{- define "appwrite.datastore.probes" -}}
startupProbe:
  {{- toYaml .handler | nindent 2 }}
  periodSeconds: 5
  timeoutSeconds: 5
  failureThreshold: 60
readinessProbe:
  {{- toYaml .handler | nindent 2 }}
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
livenessProbe:
  {{- toYaml .handler | nindent 2 }}
  periodSeconds: 20
  timeoutSeconds: 5
  failureThreshold: 6
{{- end }}
