{{/*
Durable storage (FR-080, Principle VI). The class is explicit — the cluster default is never
relied on — and the claim outlives the release unless `retain: false`.
*/}}
{{- define "hl-common.pvc" -}}
{{- $s := .v.storage -}}
{{- $p := printf "%s.storage" .name -}}
{{- range $k := list "size" "storageClassName" "mountPath" -}}
{{- if not (index $s $k) -}}{{- include "hl-common.fail" (printf "required value %q is not set" (printf "%s.%s" $p $k)) -}}{{- end -}}
{{- end -}}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ include "hl-common.fullname" . }}-data
  labels:
    {{- include "hl-common.labels" . | nindent 4 }}
  {{- if $s.retain }}
  annotations:
    helm.sh/resource-policy: keep
    argocd.argoproj.io/sync-options: Prune=false,Delete=false
  {{- end }}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: {{ $s.storageClassName }}
  resources:
    requests:
      storage: {{ $s.size }}
{{- end -}}
