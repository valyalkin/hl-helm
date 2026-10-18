{{/* Call with (dict "root" $ "name" "<sa name>"). Token automount is off unless the workload opts in. */}}
{{- define "hl-common.serviceaccount" -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .name }}
  labels:
    {{- include "hl-common.labels" (dict "root" .root "name" .name) | nindent 4 }}
automountServiceAccountToken: false
{{- end -}}
