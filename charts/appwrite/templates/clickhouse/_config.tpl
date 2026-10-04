{{- define "appwrite.clickhouse.config" -}}
system-log-ttl.xml: |
  {{- .Files.Get "files/clickhouse/system-log-ttl.xml" | nindent 2 }}
logging.xml: |
  {{- .Files.Get "files/clickhouse/logging.xml" | nindent 2 }}
users.xml: |
  {{- .Files.Get "files/clickhouse/users.xml" | replace "{{USERNAME}}" .Values.clickhouse.auth.username | nindent 2 }}
{{- end }}
