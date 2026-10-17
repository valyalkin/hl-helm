{{/*
Everything one service needs. Call once per service:
  {{ include "hl-common.all" (dict "root" . "name" "web" "values" .Values.web) }}
A section can be replaced by setting `overrides.<section>: true` in the service block and
defining a template named `<chart>.override.<section>` (contracts/library-chart-interface.md).
Helm cannot test whether a template exists, hence the explicit opt-in flag.
*/}}
{{- define "hl-common.section" -}}
{{- $ctx := .ctx -}}
{{- if index $ctx.v.overrides .section -}}
{{- include (printf "%s.override.%s" $ctx.root.Chart.Name .section) $ctx -}}
{{- else -}}
{{- include (printf "hl-common.%s" .section) $ctx -}}
{{- end -}}
{{- end -}}

{{- define "hl-common.all" -}}
{{- include "hl-common.placeholders" .root -}}
{{- $v := fromYaml (include "hl-common.build" .) -}}
{{- $ctx := dict "root" .root "name" .name "v" $v -}}
{{- $parts := list -}}
{{- $parts = append $parts (include "hl-common.section" (dict "ctx" $ctx "section" "workload")) -}}
{{- $parts = append $parts (include "hl-common.section" (dict "ctx" $ctx "section" "service")) -}}
{{- if $v.ingress.enabled }}{{ $parts = append $parts (include "hl-common.section" (dict "ctx" $ctx "section" "ingress")) }}{{ end -}}
{{- if include "hl-common.hasConfig" $ctx }}{{ $parts = append $parts (include "hl-common.section" (dict "ctx" $ctx "section" "config")) }}{{ end -}}
{{- if or $v.secrets $v.dependencies }}{{ $sec := include "hl-common.allSecrets" $ctx | fromYaml }}{{ if $sec }}{{ $parts = append $parts (include "hl-common.section" (dict "ctx" $ctx "section" "secrets")) }}{{ end }}{{ end -}}
{{- if $v.storage.enabled }}{{ $parts = append $parts (include "hl-common.section" (dict "ctx" $ctx "section" "pvc")) }}{{ end -}}
{{- join "\n---\n" $parts -}}
{{- end -}}
