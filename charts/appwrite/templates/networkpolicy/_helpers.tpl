{{/*
Pod selector for a set of components of this release.
Usage: include "appwrite.networkPolicy.selector" (dict "root" $ "components" (list "api"))
*/}}
{{- define "appwrite.networkPolicy.selector" -}}
matchLabels:
  {{- include "appwrite.selectorLabels" .root | nindent 2 }}
matchExpressions:
  - key: app.kubernetes.io/component
    operator: In
    values:
      {{- toYaml .components | nindent 6 }}
{{- end }}

{{/*
Peer matching every pod of this release.
*/}}
{{- define "appwrite.networkPolicy.releasePeer" -}}
podSelector:
  matchLabels:
    {{- include "appwrite.selectorLabels" . | nindent 4 }}
{{- end }}

{{/*
Common NetworkPolicy metadata.
*/}}
{{- define "appwrite.networkPolicy.metadata" -}}
metadata:
  name: {{ include "appwrite.fullname" .root }}-{{ .name }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "appwrite.labels" .root | nindent 4 }}
  {{- with include "appwrite.annotations" (dict "root" .root) | trim }}{{ . | nindent 2 }}{{ end }}
{{- end }}
