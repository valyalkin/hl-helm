{{/*
Resources. Requests are always emitted; limits.memory is mandatory; limits.cpu is deliberately
left unset (CPU limits throttle without protecting the node).
*/}}
{{- define "hl-common.resources" -}}
{{- $r := .v.workload.resources -}}
{{- $lim := default dict $r.limits -}}
{{- $req := default dict $r.requests -}}
{{- if not $lim.memory -}}
{{- include "hl-common.fail" (printf "required value %q is not set" (printf "%s.workload.resources.limits.memory" .name)) -}}
{{- end -}}
requests:
  cpu: {{ default "10m" $req.cpu | quote }}
  memory: {{ default $lim.memory $req.memory | quote }}
limits:
  memory: {{ $lim.memory | quote }}
{{- with $lim.cpu }}
  cpu: {{ . | quote }}
{{- end }}
{{- end -}}
