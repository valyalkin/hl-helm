{{/*
Seed credentials into Vault before the release's workloads start (FR-078, FR-079).

A pre-install/pre-upgrade hook Job logs in to Vault with Kubernetes auth and, for each entry,
writes the path only if it is absent — so existing credentials are never rotated by a deploy.
The generated values never touch the repository or the chart's rendered output.

Call from an infrastructure chart's template:
  {{ include "hl-common.vaultProvision" . }}
reading `.Values.provision`:
  provision:
    enabled: true
    vaultAddr: http://vault.vault.svc.cluster.local:8200   # supplied, never derived
    authMount: kubernetes
    kvMount: kv
    role: provision
    image: {registry: docker.io, owner: hashicorp, name: vault, tag: "2.0.4", digest: sha256:...}
    entries:
      - path: apps/todo/postgres
        static: {username: todo}        # optional fixed, non-secret fields
        generate: [password]            # fields generated on first write
*/}}
{{- define "hl-common.vaultProvision" -}}
{{- $p := default dict .Values.provision -}}
{{- if and $p.enabled $p.entries -}}
{{- if not $p.vaultAddr -}}{{- include "hl-common.fail" "required value \"provision.vaultAddr\" is not set" -}}{{- end -}}
{{- $name := printf "%s-provision" .Release.Name | trunc 53 | trimSuffix "-" -}}
{{- $sctx := dict "root" . "name" "provision" "v" (dict "workload" (dict "image" (default dict $p.image))) -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: provisioner
  labels:
    {{- include "hl-common.labels" (dict "root" . "name" "provisioner") | nindent 4 }}
  annotations:
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-weight: "-5"
    helm.sh/hook-delete-policy: before-hook-creation
---
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ $name }}
  labels:
    {{- include "hl-common.labels" (dict "root" . "name" "provision") | nindent 4 }}
  annotations:
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-weight: "0"
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  backoffLimit: 20
  template:
    metadata:
      labels:
        {{- include "hl-common.labels" (dict "root" . "name" "provision") | nindent 8 }}
    spec:
      restartPolicy: OnFailure
      serviceAccountName: provisioner
      automountServiceAccountToken: true
      securityContext:
        runAsNonRoot: true
        runAsUser: 100
        runAsGroup: 1000
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: provision
          image: {{ include "hl-common.image" $sctx | quote }}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: [ALL]}
          env:
            - {name: VAULT_ADDR, value: {{ $p.vaultAddr | quote }}}
            - {name: HOME, value: /tmp}
          resources:
            requests: {cpu: 10m, memory: 32Mi}
            limits: {memory: 64Mi}
          volumeMounts:
            - {name: tmp, mountPath: /tmp}
          command: ["/bin/sh", "-ec"]
          args:
            - |
              JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
              VAULT_TOKEN=$(vault write -field=token auth/{{ default "kubernetes" $p.authMount }}/login role={{ default "provision" $p.role }} jwt="$JWT")
              export VAULT_TOKEN
              gen() { head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32; }
              {{- range $e := $p.entries }}
              if vault kv get -mount={{ default "kv" $p.kvMount }} {{ $e.path | quote }} >/dev/null 2>&1; then
                echo "present: {{ $e.path }}"
              else
                vault kv put -mount={{ default "kv" $p.kvMount }} {{ $e.path | quote }} \
                  {{- range $k, $v := $e.static }}
                  {{ $k }}={{ $v | quote }} \
                  {{- end }}
                  {{- range $f := $e.generate }}
                  {{ $f }}="$(gen)" \
                  {{- end }}
                  >/dev/null
                echo "created: {{ $e.path }}"
              fi
              {{- end }}
      volumes:
        - {name: tmp, emptyDir: {}}
{{- end -}}
{{- end -}}
