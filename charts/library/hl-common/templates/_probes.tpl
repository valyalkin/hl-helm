{{/*
Probes. Liveness and readiness are always emitted: a chart-supplied probe is used verbatim,
otherwise a tcpSocket probe on the first declared port. Startup is emitted only when supplied.
*/}}
{{- define "hl-common.probes" -}}
{{- $p := default dict .v.workload.probes -}}
{{- $ports := .v.service.ports -}}
{{- if not $ports -}}
{{- include "hl-common.fail" (printf "required value %q is not set" (printf "%s.service.ports" .name)) -}}
{{- end -}}
{{- $default := dict "tcpSocket" (dict "port" (first $ports).name) -}}
livenessProbe:
  {{- toYaml (default $default $p.liveness) | nindent 2 }}
readinessProbe:
  {{- toYaml (default $default $p.readiness) | nindent 2 }}
{{- with $p.startup }}
startupProbe:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
