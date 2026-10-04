{{/*
Job that runs Appwrite's data migration.
Usage: include "appwrite.migrateJob" (dict "root" $ "name" "..." "hook" true)
*/}}
{{- define "appwrite.migrateJob" -}}
{{- $root := .root }}
{{- $m := $root.Values.migrations }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .name }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- include "appwrite.componentLabels" (dict "root" $root "component" "migrate") | nindent 4 }}
  annotations:
    appwrite/version: {{ include "appwrite.version" $root | quote }}
    {{- if .hook }}
    helm.sh/hook: post-upgrade
    helm.sh/hook-weight: "0"
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
    {{- end }}
    {{- with $root.Values.commonAnnotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  backoffLimit: {{ $m.backoffLimit }}
  activeDeadlineSeconds: {{ $m.activeDeadlineSeconds }}
  template:
    metadata:
      labels:
        {{- include "appwrite.componentLabels" (dict "root" $root "component" "migrate") | nindent 8 }}
        appwrite/datastore-client: "true"
    spec:
      restartPolicy: Never
      serviceAccountName: {{ include "appwrite.serviceAccountName" $root }}
      automountServiceAccountToken: false
      enableServiceLinks: false
      {{- with include "appwrite.imagePullSecrets" $root | trim }}{{ . | nindent 6 }}{{ end }}
      securityContext:
        {{- toYaml $root.Values.podSecurityContext | nindent 8 }}
      {{- with include "appwrite.pod.scheduling" (dict "root" $root "values" dict "component" "migrate") | trim }}{{ . | nindent 6 }}{{ end }}
      initContainers:
        {{- include "appwrite.initContainer.waitForApi" $root | trim | nindent 8 }}
      containers:
        - name: migrate
          image: {{ include "appwrite.appwriteImage" $root }}
          imagePullPolicy: {{ $root.Values.image.pullPolicy }}
          command: [php, app/cli.php, migrate]
          envFrom:
            {{- include "appwrite.envFrom" $root | nindent 12 }}
          env:
            {{- include "appwrite.env" (dict "root" $root "cpuNum" "1" "extra" dict) | trim | nindent 12 }}
          securityContext:
            {{- toYaml $root.Values.containerSecurityContext | nindent 12 }}
          {{- with $m.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          volumeMounts:
            {{- include "appwrite.volumeMounts" (dict "root" $root) | nindent 12 }}
      volumes:
        {{- include "appwrite.volumes" (dict "root" $root) | nindent 8 }}
{{- end }}
