{{/* Required values. Every template calls ingress-tls.validate first, so a missing value fails the
whole release with one clear message. */}}
{{- define "ingress-tls.validate" -}}
{{- $_ := include "ingress-tls.domain" . -}}
{{- end -}}

{{- define "ingress-tls.domain" -}}
{{- include "hl-common.required" (dict "path" "domain" "value" .Values.domain) -}}
{{- end -}}

{{/* Namespace shared by the Certificate and the default TLSStore. */}}
{{- define "ingress-tls.storeNamespace" -}}
{{- default .Release.Namespace .Values.tlsStore.namespace -}}
{{- end -}}

{{- define "ingress-tls.acmeServer" -}}
{{- if eq .Values.acme.server "production" -}}
https://acme-v02.api.letsencrypt.org/directory
{{- else -}}
https://acme-staging-v02.api.letsencrypt.org/directory
{{- end -}}
{{- end -}}

{{/* Labels for a named custom resource, as hl-common renders them. */}}
{{- define "ingress-tls.labels" -}}
{{- include "hl-common.labels" (dict "root" .root "name" .name) -}}
{{- end -}}
