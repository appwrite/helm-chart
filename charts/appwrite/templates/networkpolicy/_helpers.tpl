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

{{/*
Peer matching every pod in the build namespace.
*/}}
{{- define "appwrite.networkPolicy.buildsPeer" -}}
namespaceSelector:
  matchLabels:
    kubernetes.io/metadata.name: {{ include "appwrite.builds.namespace" . }}
{{- end }}

{{/*
ipBlock peers for public addresses only: everything except private,
loopback, link-local (cloud metadata), CGNAT, special-purpose and multicast
ranges, Azure's WireServer, and any extra CIDRs given.
Usage: include "appwrite.networkPolicy.publicPeers" (dict "denied" (list "203.0.113.0/24") "ipv6" true)
*/}}
{{- define "appwrite.networkPolicy.publicPeers" -}}
{{- $v4 := list "0.0.0.0/8" "10.0.0.0/8" "100.64.0.0/10" "127.0.0.0/8" "169.254.0.0/16" "172.16.0.0/12" "192.0.0.0/24" "192.168.0.0/16" "198.18.0.0/15" "224.0.0.0/4" "240.0.0.0/4" "168.63.129.16/32" }}
{{- $v6 := list "::1/128" "fc00::/7" "fe80::/10" "ff00::/8" }}
{{- range .denied | default list }}
{{- if contains ":" . }}{{ $v6 = append $v6 . }}{{ else }}{{ $v4 = append $v4 . }}{{ end }}
{{- end }}
- ipBlock:
    cidr: 0.0.0.0/0
    except:
      {{- toYaml ($v4 | uniq) | nindent 6 }}
{{- if .ipv6 }}
- ipBlock:
    cidr: ::/0
    except:
      {{- toYaml ($v6 | uniq) | nindent 6 }}
{{- end }}
{{- end }}
