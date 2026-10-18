# vault (bootstrap tier)

Wraps the upstream `vault` chart 0.34.1 (Vault 2.0.4): standalone mode, file storage, UI and
injector off. Secrets are delivered by Vault Secrets Operator, not by sidecars.

This chart reads **no** secret (FR-056): a cold rebuild installs Vault before anything that could
need it. A policy check fails the build if a bootstrap chart declares a secret reference.

## Storage, backup and restore

- Data lives on the `data-vault-0` PVC (`local-path`, 1Gi, ReadWriteOnce), created by the
  StatefulSet's volume claim template and therefore **not deleted by `helm uninstall`**.
- Back up by stopping writes and copying the PVC's directory on the node
  (`/var/lib/rancher/k3s/storage/pvc-*_vault_data-vault-0`), or snapshot the node's disk. Restore
  by placing that directory back before starting the pod, then unseal.
- The unseal key and root token are written by `bootstrap/vault-init.sh` to
  `~/.hl-helm/vault-init.json`, outside the repository. **Back that file up away from this
  cluster.** Without it a restarted Vault cannot be unsealed and its data is unreadable.
- A restarted Vault is sealed. Probes accept the sealed state so the pod is reachable; run
  `bootstrap/vault-init.sh` to unseal. Workloads already running keep their Kubernetes Secrets.

## Deviation from the constitution

None. (Licence note: Vault is BUSL; homelab use is non-competing. OpenBao is a values-level swap.)

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| vault.global.enabled | bool | `true` |  |
| vault.injector.enabled | bool | `false` |  |
| vault.server.auditStorage.enabled | bool | `false` |  |
| vault.server.dataStorage.accessMode | string | `"ReadWriteOnce"` |  |
| vault.server.dataStorage.enabled | bool | `true` |  |
| vault.server.dataStorage.size | string | `"1Gi"` |  |
| vault.server.dataStorage.storageClass | string | `"local-path"` |  |
| vault.server.image.repository | string | `"hashicorp/vault"` |  |
| vault.server.image.tag | string | `"2.0.4"` |  |
| vault.server.livenessProbe.enabled | bool | `true` |  |
| vault.server.livenessProbe.initialDelaySeconds | int | `60` |  |
| vault.server.livenessProbe.path | string | `"/v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204"` |  |
| vault.server.readinessProbe.enabled | bool | `true` |  |
| vault.server.readinessProbe.path | string | `"/v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204"` |  |
| vault.server.resources.limits.memory | string | `"256Mi"` |  |
| vault.server.resources.requests.cpu | string | `"50m"` |  |
| vault.server.resources.requests.memory | string | `"128Mi"` |  |
| vault.server.standalone.config | string | `"ui = true\nlistener \"tcp\" {\n  tls_disable = 1\n  address = \"[::]:8200\"\n  cluster_address = \"[::]:8201\"\n}\nstorage \"file\" {\n  path = \"/vault/data\"\n}\n"` |  |
| vault.server.standalone.enabled | bool | `true` |  |
| vault.ui.enabled | bool | `false` |  |
