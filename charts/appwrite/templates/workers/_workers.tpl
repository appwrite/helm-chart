{{/*
Queues Appwrite's worker consumes, keyed by their values.yaml name, with the
concurrency Appwrite uses for each (app/config/workers.php) and the storage
they need.
*/}}
{{- define "appwrite.workers.catalog" -}}
statsUsage: {name: stats-usage, coroutines: 8}
statsResources: {name: stats-resources, coroutines: 1}
webhooks: {name: webhooks, coroutines: 8}
deletes: {name: deletes, coroutines: 8, storage: true}
databases: {name: databases, coroutines: 1}
builds: {name: builds, coroutines: 8, storage: true}
jobs: {name: jobs, coroutines: 8, storage: true}
screenshots: {name: screenshots, coroutines: 8, storage: true}
certificates: {name: certificates, coroutines: 8, storage: true, certbot: true}
executions: {name: executions, coroutines: 8}
functions: {name: functions, coroutines: 8}
mails: {name: mails, coroutines: 1}
notifications: {name: notifications, coroutines: 1}
messaging: {name: messaging, coroutines: 1, storage: true}
migrations: {name: migrations, coroutines: 1, storage: true}
{{- end }}

{{/*
Worker Deployments to render, as a YAML list. Each item has:
  component   component label and name suffix
  queues      list of queue names, or ["all"]
  values      replicaCount, processes, maxCoroutines, cpuNum, resources, autoscaling
  storage     mounts /storage
  certbot     mounts writable certbot directories
  singleton   consumes the databases queue: one replica, recreated on update
*/}}
{{- define "appwrite.workers.deployments" -}}
{{- $w := .Values.workers }}
{{- $catalog := include "appwrite.workers.catalog" . | fromYaml }}
{{- $byName := dict }}
{{- range $key, $q := $catalog }}
{{- $_ := set $byName $q.name (merge (dict "key" $key) $q) }}
{{- end }}
{{- $out := list }}
{{- if eq $w.mode "combined" }}
{{- $out = append $out (dict "component" "worker" "queues" (list "all") "values" $w.combined "storage" true "certbot" true "singleton" true) }}
{{- else if eq $w.mode "separate" }}
{{- range $key, $q := $catalog }}
{{- $v := get $w.queues $key | default dict }}
{{- if $v.enabled }}
{{- $values := deepCopy $v }}
{{- $_ := set $values "resources" ($v.resources | default $w.resources) }}
{{- $out = append $out (dict "component" (printf "worker-%s" $q.name) "queues" (list $q.name) "values" $values "storage" ($q.storage | default false) "certbot" ($q.certbot | default false) "singleton" (eq $key "databases")) }}
{{- end }}
{{- end }}
{{- else if eq $w.mode "grouped" }}
{{- range $group, $g := $w.groups }}
{{- $g = merge (dict "queues" list) $g }}
{{- $storage := false }}
{{- $certbot := false }}
{{- $coroutines := 0 }}
{{- range $g.queues }}
{{- $q := get $byName . | default dict }}
{{- $storage = or $storage ($q.storage | default false) }}
{{- $certbot = or $certbot ($q.certbot | default false) }}
{{- $coroutines = add $coroutines ($q.coroutines | default 1) }}
{{- end }}
{{- $values := deepCopy $g }}
{{- range $key, $default := dict "replicaCount" 1 "processes" 1 }}
{{- if not (hasKey $values $key) }}{{ $_ := set $values $key $default }}{{ end }}
{{- end }}
{{- $_ := set $values "resources" ($g.resources | default $w.resources) }}
{{- if not $g.maxCoroutines }}
{{- /* Several queues share one pool: size it for the sum of their concurrency. */}}
{{- $_ := set $values "maxCoroutines" (max $coroutines 1) }}
{{- end }}
{{- $out = append $out (dict "component" (printf "worker-%s" $group) "queues" $g.queues "values" $values "storage" $storage "certbot" $certbot "singleton" (has "databases" $g.queues)) }}
{{- end }}
{{- end }}
{{- toYaml $out }}
{{- end }}

{{/*
Queue names no worker Deployment consumes. Their jobs pile up in Redis.
*/}}
{{- define "appwrite.workers.unconsumed" -}}
{{- $consumed := list }}
{{- range (include "appwrite.workers.deployments" . | fromYamlArray) }}
{{- if or (gt (int (.values.replicaCount | default 0)) 0) (and .values.autoscaling .values.autoscaling.enabled) }}
{{- $consumed = concat $consumed .queues }}
{{- end }}
{{- end }}
{{- $missing := list }}
{{- if not (has "all" $consumed) }}
{{- range $key, $q := include "appwrite.workers.catalog" . | fromYaml }}
{{- if not (has $q.name $consumed) }}
{{- $missing = append $missing $q.name }}
{{- end }}
{{- end }}
{{- end }}
{{- join ", " (sortAlpha $missing) }}
{{- end }}
