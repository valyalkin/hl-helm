{{/*
Render-time failure. Every message starts with "hl-common:" and names the offending value.
*/}}
{{- define "hl-common.fail" -}}
{{- fail (printf "hl-common: %s" .) -}}
{{- end -}}

{{/*
Assert a value is set. Call with (dict "path" "web.workload.resources.limits.memory" "value" $v).
*/}}
{{- define "hl-common.required" -}}
{{- if not .value -}}
{{- include "hl-common.fail" (printf "required value %q is not set" .path) -}}
{{- end -}}
{{- .value -}}
{{- end -}}

{{/*
Reference-chart placeholder guard (FR-043). A chart shipped as a copy source declares, in
Chart.yaml annotations:
  hl-common/reference-name: <the name it ships under>
  hl-common/placeholders:   "<values.path>=<shipped value> ..."
While the chart still bears that name nothing is checked, so the reference itself deploys. Once an
operator renames the chart, any listed parameter still holding its shipped value fails rendering
and names the parameter.
*/}}
{{- define "hl-common.placeholders" -}}
{{- $a := default dict .Chart.Annotations -}}
{{- $ref := index $a "hl-common/reference-name" -}}
{{- if and $ref (ne $ref .Chart.Name) -}}
{{- range $pair := splitList " " (default "" (index $a "hl-common/placeholders")) -}}
{{- if $pair -}}
{{- $kv := splitList "=" $pair -}}
{{- $v := $.Values -}}
{{- range $seg := splitList "." (first $kv) -}}
{{- if kindIs "map" $v }}{{ $v = index $v $seg }}{{ else }}{{ $v = "" }}{{ end -}}
{{- end -}}
{{- if eq (toString $v) (last $kv) -}}
{{- include "hl-common.fail" (printf "chart %q still holds the reference placeholder %q for %q; change it to this application's own value" $.Chart.Name (last $kv) (first $kv)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
