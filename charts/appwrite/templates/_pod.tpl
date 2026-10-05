{{/*
Scheduling fields for a pod spec: nodeSelector, tolerations, affinity,
topologySpreadConstraints and priorityClassName. Component values fall back
to `defaults` key by key.

Usage: include "appwrite.pod.scheduling" (dict
  "root" $                  root context
  "values" .Values.api      component values
  "parent" .Values.workers  optional group values consulted before `defaults`
  "component" "api"         component name, used for default spread labels
  "spread" true             add a soft spread across nodes when none is configured
  "storage" true            pod mounts the /storage volume
)
*/}}
{{- define "appwrite.pod.scheduling" -}}
{{- $root := .root }}
{{- $d := $root.Values.defaults }}
{{- $parent := .parent | default dict }}
{{- $v := .values }}
{{- $nodeSelector := $v.nodeSelector | default $parent.nodeSelector | default $d.nodeSelector }}
{{- $tolerations := $v.tolerations | default $parent.tolerations | default $d.tolerations }}
{{- $affinity := deepCopy ($v.affinity | default $parent.affinity | default $d.affinity | default dict) }}
{{- $spread := $v.topologySpreadConstraints | default $parent.topologySpreadConstraints | default $d.topologySpreadConstraints }}
{{- $priorityClassName := $v.priorityClassName | default $parent.priorityClassName | default $d.priorityClassName }}
{{- if and .storage (include "appwrite.storage.colocate" $root) }}
{{- /* A ReadWriteOnce volume can only be attached to one node: keep every pod that mounts it together. */}}
{{- $term := dict
  "labelSelector" (dict "matchLabels" (dict "app.kubernetes.io/instance" $root.Release.Name "appwrite/storage" "shared"))
  "topologyKey" "kubernetes.io/hostname" }}
{{- $podAffinity := get $affinity "podAffinity" | default dict }}
{{- $required := get $podAffinity "requiredDuringSchedulingIgnoredDuringExecution" | default list }}
{{- $_ := set $podAffinity "requiredDuringSchedulingIgnoredDuringExecution" (append $required $term) }}
{{- $_ := set $affinity "podAffinity" $podAffinity }}
{{- end }}
{{- with $nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if $spread }}
topologySpreadConstraints:
  {{- range $spread }}
  {{- $c := deepCopy . }}
  {{- if not (hasKey $c "labelSelector") }}
  {{- $_ := set $c "labelSelector" (dict "matchLabels" (include "appwrite.componentSelectorLabels" (dict "root" $root "component" $.component) | fromYaml)) }}
  {{- end }}
  - {{- toYaml $c | nindent 4 }}
  {{- end }}
{{- else if .spread }}
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        {{- include "appwrite.componentSelectorLabels" (dict "root" $root "component" .component) | nindent 8 }}
{{- end }}
{{- with $priorityClassName }}
priorityClassName: {{ . }}
{{- end }}
{{- end }}

{{/*
Pod labels and annotations: component values merged over `defaults`.
Usage: include "appwrite.pod.metadata" (dict "root" $ "values" .Values.api "parent" (dict) "component" "api" "annotations" (dict) "labels" (dict))
*/}}
{{- define "appwrite.pod.metadata" -}}
{{- $root := .root }}
{{- $parent := .parent | default dict }}
{{- $labels := merge (dict) (.labels | default dict) (.values.podLabels | default dict) ($parent.podLabels | default dict) ($root.Values.defaults.podLabels | default dict) }}
{{- $annotations := merge (dict) (.annotations | default dict) (.values.podAnnotations | default dict) ($parent.podAnnotations | default dict) ($root.Values.defaults.podAnnotations | default dict) }}
labels:
  {{- include "appwrite.podLabels" (dict "root" $root "component" .component) | nindent 2 }}
  {{- with $labels }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- with $annotations }}
annotations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Checksums of the env ConfigMap, the chart Secret and the secretConfig Secret,
so Appwrite pods roll when configuration changes.
*/}}
{{- define "appwrite.pod.checksums" -}}
{{- dict
  "checksum/config" (include "appwrite.env.config" . | sha256sum)
  "checksum/secret" (include "appwrite.secret.data" . | sha256sum)
  "checksum/secret-env" (toYaml (.Values.appwrite.secretConfig | default dict) | sha256sum)
  | toYaml }}
{{- end }}

{{/*
Paths under /storage that live on the shared volume. /storage/cache is a
per-pod emptyDir: cached files are only served when the database knows about
them, so a pod-local cache is safe.
*/}}
{{- define "appwrite.storage.paths" -}}
uploads,imports,config,certificates,functions,sites,builds
{{- end }}

{{/*
Volumes for an Appwrite pod.
Usage: include "appwrite.volumes" (dict "root" $ "storage" true "certbot" true)
*/}}
{{- define "appwrite.volumes" -}}
- name: tmp
  emptyDir: {}
- name: home
  emptyDir: {}
- name: cache
  emptyDir: {}
{{- if .storage }}
- name: storage
  {{- if .root.Values.persistence.enabled }}
  persistentVolumeClaim:
    claimName: {{ .root.Values.persistence.existingClaim | default (printf "%s-storage" (include "appwrite.fullname" .root)) }}
  {{- else }}
  emptyDir: {}
  {{- end }}
{{- end }}
{{- if .certbot }}
- name: letsencrypt
  emptyDir: {}
{{- end }}
{{- end }}

{{/*
Volume mounts for an Appwrite container.
Usage: include "appwrite.volumeMounts" (dict "root" $ "storage" true "certbot" true)
*/}}
{{- define "appwrite.volumeMounts" -}}
- name: tmp
  mountPath: /tmp
{{- /* Swoole keeps lock files for coroutine DNS lookups in $HOME/.swoole. */}}
- name: home
  mountPath: /home/www-data
- name: cache
  mountPath: /storage/cache
{{- if .storage }}
{{- range (include "appwrite.storage.paths" .root | splitList ",") }}
- name: storage
  mountPath: /storage/{{ . }}
  subPath: {{ . }}
{{- end }}
{{- end }}
{{- if .certbot }}
{{- /* certbot keeps its working state here before Appwrite moves certificates to /storage/certificates. */}}
- name: letsencrypt
  mountPath: /etc/letsencrypt
  subPath: etc
- name: letsencrypt
  mountPath: /var/lib/letsencrypt
  subPath: lib
- name: letsencrypt
  mountPath: /var/log/letsencrypt
  subPath: log
{{- end }}
{{- end }}

{{/*
Resources for the chart's init containers.
*/}}
{{- define "appwrite.initContainer.resources" -}}
requests:
  cpu: 10m
  memory: 32Mi
limits:
  memory: 128Mi
{{- end }}

{{/*
Init container that waits until TCP endpoints accept connections.
Usage: include "appwrite.initContainer.waitForTcp" (dict "root" $ "name" "wait-for-datastores" "targets" (list "host:port"))
*/}}
{{- define "appwrite.initContainer.waitForTcp" -}}
- name: {{ .name }}
  image: {{ include "appwrite.appwriteImage" .root }}
  imagePullPolicy: {{ .root.Values.image.pullPolicy }}
  command:
    - sh
    - -c
    - |
      for target in $WAIT_FOR; do
        host="${target%:*}"; port="${target##*:}"
        until php -r "exit(@fsockopen('$host', $port, \$e, \$s, 2) ? 0 : 1);"; do
          echo "waiting for $target"
          sleep 2
        done
        echo "$target is reachable"
      done
  env:
    - name: WAIT_FOR
      value: {{ join " " .targets | quote }}
  securityContext:
    {{- toYaml .root.Values.containerSecurityContext | nindent 4 }}
  resources:
    {{- include "appwrite.initContainer.resources" . | nindent 4 }}
{{- end }}

{{/*
Init container that waits until the API answers, which means the database
schema exists. Appwrite's CLI tasks and workers exit if they start before it.
*/}}
{{- define "appwrite.initContainer.waitForApi" -}}
{{- $host := include "appwrite.api.internalHost" . }}
- name: wait-for-api
  image: {{ include "appwrite.appwriteImage" . }}
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  command:
    - sh
    - -c
    - |
      until curl -fsS -o /dev/null --max-time 5 -H "Host: {{ $host }}" "http://{{ $host }}:{{ .Values.api.service.port }}/v1/health/version"; do
        echo "waiting for the Appwrite API"
        sleep 3
      done
  securityContext:
    {{- toYaml .Values.containerSecurityContext | nindent 4 }}
  resources:
    {{- include "appwrite.initContainer.resources" . | nindent 4 }}
{{- end }}

{{/*
host:port targets of the datastores Appwrite needs before it can start.
*/}}
{{- define "appwrite.datastoreTargets" -}}
{{- $db := include "appwrite.db" . | fromYaml }}
{{- $redis := include "appwrite.redis" . | fromYaml }}
{{- $ch := include "appwrite.clickhouse" . | fromYaml }}
{{- join "," (list (printf "%s:%s" $db.host ($db.port | toString)) (printf "%s:%s" $redis.host ($redis.port | toString)) $ch.address) }}
{{- end }}
