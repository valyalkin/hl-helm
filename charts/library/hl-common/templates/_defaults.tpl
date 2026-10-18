{{/*
Authoritative defaults for one service block, and the merge that applies them.
mergo treats false/0 as empty, so the four keys whose default is truthy are re-applied by hand.
*/}}
{{- define "hl-common.defaults" -}}
workload:
  kind: Deployment
  replicas: 1
  automountServiceAccountToken: false
  image:
    registry: ghcr.io
    owner: valyalkin
  resources:
    requests:
      cpu: 10m
  tmpDirs: []
service:
  ports: []
ingress:
  enabled: false
  path: /
  className: traefik
  tls: {}
storage:
  enabled: false
  retain: true
config:
  values: {}
  files: []
  restartOnChange: true
secrets: {}
dependencies: {}
overrides: {}
{{- end -}}

{{/* Call with (dict "name" "web" "values" .Values.web). Returns YAML. */}}
{{- define "hl-common.build" -}}
{{- $in := deepCopy (default dict .values) -}}
{{- $out := mustMergeOverwrite (fromYaml (include "hl-common.defaults" .)) $in -}}
{{- $w := default dict $in.workload -}}
{{- $s := default dict $in.storage -}}
{{- $c := default dict $in.config -}}
{{- if hasKey $w "replicas" }}{{ $_ := set $out.workload "replicas" $w.replicas }}{{ end -}}
{{- if hasKey $w "automountServiceAccountToken" }}{{ $_ := set $out.workload "automountServiceAccountToken" $w.automountServiceAccountToken }}{{ end -}}
{{- if hasKey $s "retain" }}{{ $_ := set $out.storage "retain" $s.retain }}{{ end -}}
{{- if hasKey $c "restartOnChange" }}{{ $_ := set $out.config "restartOnChange" $c.restartOnChange }}{{ end -}}
{{- toYaml $out -}}
{{- end -}}
