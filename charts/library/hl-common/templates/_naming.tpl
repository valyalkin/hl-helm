{{/*
Naming and labels. Every helper takes the service context built by hl-common.all:
  (dict "root" $ "name" "<service key>" "v" <merged service values>)
A chart rendering a custom resource builds the same dict: (dict "root" $ "name" "web").
*/}}

{{/* Release-scoped resource name, truncated to 53 chars so suffixes stay under the 63 limit. */}}
{{- define "hl-common.fullname" -}}
{{- if or (not .name) (eq .name .root.Release.Name) -}}
{{- .root.Release.Name | trunc 53 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .root.Release.Name .name | trunc 53 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Release-scoped name for custom resources, matching the foundation's naming (FR-002). */}}
{{- define "hl-common.name" -}}
{{- include "hl-common.fullname" . -}}
{{- end -}}

{{- define "hl-common.selectorLabels" -}}
app.kubernetes.io/name: {{ default .root.Release.Name .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end }}

{{- define "hl-common.labels" -}}
{{ include "hl-common.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/part-of: {{ .root.Chart.Name }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- with .version }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- end -}}
