{{- define "hl-common.service" -}}
{{- if not .v.service.ports -}}
{{- include "hl-common.fail" (printf "required value %q is not set" (printf "%s.service.ports" .name)) -}}
{{- end -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "hl-common.fullname" . }}
  labels:
    {{- include "hl-common.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    {{- include "hl-common.selectorLabels" . | nindent 4 }}
  ports:
    {{- range .v.service.ports }}
    - name: {{ .name }}
      port: {{ .port }}
      targetPort: {{ default .port .targetPort }}
      protocol: {{ default "TCP" .protocol }}
    {{- end }}
{{- end -}}
