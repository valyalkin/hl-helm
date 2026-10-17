{{/*
Secret references (FR-026, FR-028) and dependency references (FR-069, FR-081).

secrets:
  <name>:
    vaultPath: apps/todo/db     # required: path in the KV mount
    keys: {password: DB_PASSWORD}   # Vault key -> environment variable
    mount: kv                   # optional
    refreshAfter: 1h            # optional
    rolloutRestart: true        # optional: restart the workload when the secret rotates
    type: Opaque                # optional: kubernetes.io/dockerconfigjson for a pull secret

dependencies:
  <name>:
    host: postgres-rw.postgres.svc.cluster.local   # required, supplied — never derived
    port: 5432                                    # required
    credentials: <a secret reference as above>    # optional
    optional: false                               # true = the consumer degrades instead of failing

No field carries secret material; only a path into the store.
*/}}

{{/* secrets plus each dependency's credentials, as one YAML map keyed by logical name. */}}
{{- define "hl-common.allSecrets" -}}
{{- $all := deepCopy (default dict .v.secrets) -}}
{{- range $n, $d := (default dict .v.dependencies) -}}
{{- with $d.credentials }}{{ $_ := set $all (printf "%s-credentials" $n) . }}{{ end -}}
{{- end -}}
{{- toYaml $all -}}
{{- end -}}

{{- define "hl-common.secretName" -}}
{{- printf "%s-%s" (include "hl-common.fullname" .ctx) .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "hl-common.secrets" -}}
{{- $ctx := . -}}
{{- $docs := list -}}
{{- $all := fromYaml (include "hl-common.allSecrets" .) -}}
{{- range $n := keys $all | sortAlpha -}}
{{- $s := index $all $n -}}
{{- if not $s.vaultPath -}}
{{- include "hl-common.fail" (printf "required value %q is not set" (printf "%s.secrets.%s.vaultPath" $ctx.name $n)) -}}
{{- end -}}
{{- $doc := include "hl-common.vaultStaticSecret" (dict "ctx" $ctx "name" $n "s" $s) -}}
{{- $docs = append $docs $doc -}}
{{- end -}}
{{- join "\n---\n" $docs -}}
{{- end -}}

{{- define "hl-common.vaultStaticSecret" -}}
{{- $s := .s -}}
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: {{ include "hl-common.secretName" . }}
  labels:
    {{- include "hl-common.labels" .ctx | nindent 4 }}
spec:
  vaultAuthRef: {{ .ctx.root.Release.Name }}
  mount: {{ default "kv" $s.mount }}
  type: kv-v2
  path: {{ $s.vaultPath }}
  refreshAfter: {{ default "1h" $s.refreshAfter }}
  destination:
    create: true
    name: {{ include "hl-common.secretName" . }}
    type: {{ default "Opaque" $s.type }}
  {{- if ne false $s.rolloutRestart }}
  rolloutRestartTargets:
    - kind: {{ .ctx.v.workload.kind }}
      name: {{ include "hl-common.fullname" .ctx }}
  {{- end }}
{{- end -}}

{{- define "hl-common.envName" -}}
{{- . | upper | replace "-" "_" | replace "." "_" -}}
{{- end -}}

{{/* env entries from secret references and dependency references, for custom workloads too. */}}
{{- define "hl-common.secretEnv" -}}
{{- $ctx := . -}}
{{- $all := fromYaml (include "hl-common.allSecrets" .) -}}
{{- range $n := keys $all | sortAlpha }}
{{- $s := index $all $n }}
{{- if ne (default "Opaque" $s.type) "kubernetes.io/dockerconfigjson" }}
{{- range $k := keys (default dict $s.keys) | sortAlpha }}
- name: {{ index $s.keys $k }}
  valueFrom:
    secretKeyRef:
      name: {{ include "hl-common.secretName" (dict "ctx" $ctx "name" $n) }}
      key: {{ $k }}
{{- end }}
{{- end }}
{{- end }}
{{- range $n := keys (default dict $ctx.v.dependencies) | sortAlpha }}
{{- $d := index $ctx.v.dependencies $n }}
{{- if not $d.host }}{{ include "hl-common.fail" (printf "required value %q is not set" (printf "%s.dependencies.%s.host" $ctx.name $n)) }}{{ end }}
{{- if not $d.port }}{{ include "hl-common.fail" (printf "required value %q is not set" (printf "%s.dependencies.%s.port" $ctx.name $n)) }}{{ end }}
- name: {{ include "hl-common.envName" $n }}_HOST
  value: {{ $d.host | quote }}
- name: {{ include "hl-common.envName" $n }}_PORT
  value: {{ $d.port | quote }}
- name: {{ include "hl-common.envName" $n }}_OPTIONAL
  value: {{ ternary "true" "false" (eq true $d.optional) | quote }}
{{- end }}
{{- end -}}

{{/* Pod annotations recording each dependency and whether the workload tolerates its absence. */}}
{{- define "hl-common.dependencyAnnotations" -}}
{{- range $n := keys (default dict .v.dependencies) | sortAlpha }}
{{- $d := index $.v.dependencies $n }}
hl-common/dependency.{{ $n }}: {{ ternary "optional" "required" (eq true $d.optional) }}
{{- end }}
{{- end -}}
