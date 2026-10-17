{{/*
A complete pod spec for one service: standard container, probes, resources, hardened security
context, config and tmp mounts. Used by hl-common.workload and available to custom controllers
(CronJob, Job) that want the same container.
*/}}
{{- define "hl-common.podSpec" -}}
{{- $w := .v.workload -}}
{{- $hasCfg := include "hl-common.hasConfig" . -}}
serviceAccountName: {{ default .root.Release.Name $w.serviceAccountName }}
automountServiceAccountToken: {{ $w.automountServiceAccountToken }}
securityContext:
  {{- toYaml (default (dict "runAsNonRoot" true "runAsUser" 10001 "runAsGroup" 10001 "fsGroup" 10001 "seccompProfile" (dict "type" "RuntimeDefault")) $w.podSecurityContext) | nindent 2 }}
{{- with $w.image.pullSecret }}
imagePullSecrets:
  - name: {{ . }}
{{- end }}
containers:
  - name: {{ default .root.Release.Name .name }}
    image: {{ include "hl-common.image" . | quote }}
    imagePullPolicy: IfNotPresent
    securityContext:
      {{- toYaml (default (dict "allowPrivilegeEscalation" false "readOnlyRootFilesystem" true "capabilities" (dict "drop" (list "ALL"))) $w.securityContext) | nindent 6 }}
    {{- with $w.command }}
    command:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $w.args }}
    args:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    ports:
      {{- range .v.service.ports }}
      - name: {{ .name }}
        containerPort: {{ default .port .targetPort }}
        protocol: {{ default "TCP" .protocol }}
      {{- end }}
    {{- with $w.env }}
    env:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- include "hl-common.probes" . | nindent 4 }}
    resources:
      {{- include "hl-common.resources" . | nindent 6 }}
    {{- if or $hasCfg $w.tmpDirs }}
    volumeMounts:
      {{- if $hasCfg }}
      - name: config
        mountPath: {{ .v.config.mountPath }}
        readOnly: true
      {{- end }}
      {{- range $i, $d := $w.tmpDirs }}
      - name: tmp-{{ $i }}
        mountPath: {{ $d }}
      {{- end }}
    {{- end }}
{{- if or $hasCfg $w.tmpDirs }}
volumes:
  {{- if $hasCfg }}
  - name: config
    configMap:
      name: {{ include "hl-common.fullname" . }}
  {{- end }}
  {{- range $i, $d := $w.tmpDirs }}
  - name: tmp-{{ $i }}
    emptyDir: {}
  {{- end }}
{{- end }}
{{- end -}}
