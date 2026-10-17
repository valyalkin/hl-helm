{{/*
One application's namespace, service account and VSO VaultAuth (FR-040, FR-041, FR-051).
Called once per application chart from templates/namespace.yaml:
  {{ include "hl-common.namespace" . }}
The namespace is the release namespace, which the ApplicationSet derives from the chart's
directory name. Optional chart values under `vaultAuth`: mount, role (default "apps", one Vault role shared by
every application namespace, with a policy templated on the namespace), audiences,
connectionRef, serviceAccount (default: the release name; set it when another controller
claims that name, as CloudNativePG does for a Cluster), and createNamespace (default true; infrastructure charts installed with
`helm --create-namespace` set it false and render only the service account and VaultAuth).
*/}}
{{- define "hl-common.namespace" -}}
{{- $va := default dict .Values.vaultAuth -}}
{{- $name := .Release.Namespace -}}
{{- if ne false $va.createNamespace }}
apiVersion: v1
kind: Namespace
metadata:
  name: {{ $name }}
  labels:
    {{- include "hl-common.labels" (dict "root" . "name" $name) | nindent 4 }}
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
---
{{ end -}}
{{ include "hl-common.serviceaccount" (dict "root" . "name" (default .Release.Name $va.serviceAccount)) }}
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: {{ .Release.Name }}
  namespace: {{ $name }}
  labels:
    {{- include "hl-common.labels" (dict "root" . "name" .Release.Name) | nindent 4 }}
spec:
  method: kubernetes
  mount: {{ default "kubernetes" $va.mount }}
  {{- with $va.connectionRef }}
  vaultConnectionRef: {{ . }}
  {{- end }}
  kubernetes:
    role: {{ default "apps" $va.role }}
    serviceAccount: {{ default .Release.Name $va.serviceAccount }}
    audiences:
      {{- toYaml (default (list "vault") $va.audiences) | nindent 6 }}
{{- end -}}
