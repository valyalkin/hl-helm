{{- define "hl-common.workload" -}}
{{- $kind := .v.workload.kind -}}
{{- if not (has $kind (list "Deployment" "StatefulSet")) -}}
{{- include "hl-common.fail" (printf "%s.workload.kind must be Deployment or StatefulSet, got %q" .name $kind) -}}
{{- end -}}
{{- if and .v.storage.enabled (ne $kind "StatefulSet") -}}
{{- include "hl-common.fail" (printf "%s.workload.kind must be StatefulSet when %s.storage.enabled is true" .name .name) -}}
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
      {{- $deps := include "hl-common.dependencyAnnotations" . }}
      {{- $cfg := and (include "hl-common.hasConfig" .) .v.config.restartOnChange }}
      {{- if or $deps $cfg }}
      annotations:
        {{- if $cfg }}
        checksum/config: {{ include "hl-common.configHash" . }}
        {{- end }}
        {{- with $deps }}{{ . | nindent 8 }}{{ end }}
      {{- end }}
    spec:
      {{- include "hl-common.podSpec" . | nindent 6 }}
{{- end -}}
