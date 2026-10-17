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
