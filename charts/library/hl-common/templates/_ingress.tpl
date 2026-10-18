{{/* TLS stanza is always emitted; secretName optional (unset = Traefik's default certificate, R-008). */}}
{{- define "hl-common.ingress" -}}
{{- $i := .v.ingress -}}
{{- $p := printf "%s.ingress" .name -}}
{{- if not $i.host -}}{{- include "hl-common.fail" (printf "required value %q is not set" (printf "%s.host" $p)) -}}{{- end -}}
{{- $port := $i.port -}}
{{- if not $port -}}{{- $port = (first .v.service.ports).port -}}{{- end -}}
{{- $match := false -}}
{{- range .v.service.ports }}{{ if eq (int .port) (int $port) }}{{ $match = true }}{{ end }}{{ end -}}
{{- if not $match -}}
{{- include "hl-common.fail" (printf "value %q (%v) does not match a port in %s.service.ports" (printf "%s.port" $p) $port .name) -}}
{{- end -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "hl-common.fullname" . }}
  labels:
    {{- include "hl-common.labels" . | nindent 4 }}
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  ingressClassName: {{ $i.className }}
  tls:
    - hosts:
        - {{ $i.host | quote }}
      {{- with $i.tls.secretName }}
      secretName: {{ . }}
      {{- end }}
  rules:
    - host: {{ $i.host | quote }}
      http:
        paths:
          - path: {{ $i.path }}
            pathType: Prefix
            backend:
              service:
                name: {{ include "hl-common.fullname" . }}
                port:
                  number: {{ $port }}
{{- end -}}
