# vault-secrets-operator

Vault Secrets Operator wrapper chart. Delivers `VaultStaticSecret` resources from Vault KV to Kubernetes Secrets and restarts consumers (`rolloutRestartTargets`) when a value rotates.

## Storage, backup and restore

Stateless. Nothing to back up.

## Deviation from the constitution

None. Pins upstream chart `vault-secrets-operator` 1.6.0; the default `VaultConnection` points at the in-cluster Vault address supplied in `values.yaml`.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| vault-secrets-operator.controller.manager.resources.limits.memory | string | `"128Mi"` |  |
| vault-secrets-operator.controller.manager.resources.requests.cpu | string | `"10m"` |  |
| vault-secrets-operator.controller.manager.resources.requests.memory | string | `"64Mi"` |  |
| vault-secrets-operator.defaultVaultConnection.address | string | `"http://vault.vault.svc.cluster.local:8200"` |  |
| vault-secrets-operator.defaultVaultConnection.enabled | bool | `true` |  |
| vault-secrets-operator.defaultVaultConnection.skipTLSVerify | bool | `false` |  |
