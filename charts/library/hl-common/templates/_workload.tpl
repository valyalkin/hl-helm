{{- define "hl-common.workload" -}}
{{- $kind := .v.workload.kind -}}
{{- if not (has $kind (list "Deployment" "StatefulSet")) -}}
{{- include "hl-common.fail" (printf "%s.workload.kind must be Deployment or StatefulSet, got %q" .name $kind) -}}
{{- end -}}
{{- $ver := include "hl-common.imageVersion" . -}}
{{- $ctx := dict "root" .root "name" .name "v" .v "version" $ver -}}
apiVersion: apps/v1
kind: {{ $kind }}
metadata:
  name: {{ include "hl-common.fullname" . }}
  labels:
    {{- include "hl-common.labels" $ctx | nindent 4 }}
spec:
  replicas: {{ .v.workload.replicas }}
  {{- if eq $kind "StatefulSet" }}
  serviceName: {{ include "hl-common.fullname" . }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "hl-common.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "hl-common.labels" $ctx | nindent 8 }}
      {{- if and (include "hl-common.hasConfig" .) .v.config.restartOnChange }}
      annotations:
        checksum/config: {{ include "hl-common.configHash" . }}
      {{- end }}
    spec:
      {{- include "hl-common.podSpec" . | nindent 6 }}
{{- end -}}
