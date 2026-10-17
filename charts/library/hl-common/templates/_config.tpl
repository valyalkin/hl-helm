{{/*
ConfigMap from config.values (one key per entry; maps are rendered as YAML) and config.files
(verbatim from the consuming chart's files/). Secret-shaped keys and duplicate keys fail rendering.
*/}}
{{- define "hl-common.configData" -}}
{{- $c := .v.config -}}
{{- $data := dict -}}
{{- range $k, $val := $c.values -}}
{{- if regexMatch "(?i)(password|passwd|secret|token|api[_-]?key|private[_-]?key)" $k -}}
{{- include "hl-common.fail" (printf "%s.config.values key %q looks like secret material; use a secrets reference" $.name $k) -}}
{{- end -}}
{{- $_ := set $data $k (ternary (toYaml $val) (toString $val) (kindIs "map" $val)) -}}
{{- end -}}
{{- range $c.files -}}
{{- $key := base . -}}
{{- if hasKey $data $key -}}
{{- include "hl-common.fail" (printf "%s.config: key %q appears in both values and files" $.name $key) -}}
{{- end -}}
{{- $content := $.root.Files.Get (printf "files/%s" .) -}}
{{- if not $content -}}
{{- include "hl-common.fail" (printf "%s.config.files: files/%s is missing or empty" $.name .) -}}
{{- end -}}
{{- $_ := set $data $key $content -}}
{{- end -}}
{{- toYaml $data -}}
{{- end -}}

{{- define "hl-common.hasConfig" -}}
{{- if or .v.config.values .v.config.files -}}true{{- end -}}
{{- end -}}

{{/* Hash of rendered configuration, for pod-template annotations (FR-037). */}}
{{- define "hl-common.configHash" -}}
{{- include "hl-common.configData" . | sha256sum -}}
{{- end -}}

{{- define "hl-common.config" -}}
{{- if include "hl-common.hasConfig" . -}}
{{- if not .v.config.mountPath -}}
{{- include "hl-common.fail" (printf "required value %q is not set" (printf "%s.config.mountPath" .name)) -}}
{{- end -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "hl-common.fullname" . }}
  labels:
    {{- include "hl-common.labels" . | nindent 4 }}
data:
  {{- include "hl-common.configData" . | nindent 2 }}
{{- end -}}
{{- end -}}
