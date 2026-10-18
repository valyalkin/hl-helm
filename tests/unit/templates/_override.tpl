{{- define "hl-test.override.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "hl-common.name" . }}
  labels:
    {{- include "hl-common.labels" . | nindent 4 }}
    overridden: "true"
spec:
  type: NodePort
  selector:
    {{- include "hl-common.selectorLabels" . | nindent 4 }}
  ports:
    - port: 80
{{- end -}}
