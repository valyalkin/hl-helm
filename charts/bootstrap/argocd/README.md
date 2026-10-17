# argocd

Argo CD wrapper chart, installed **last** by `bootstrap/install.sh`. It reconciles the application tier only (`charts/apps/*`) through `argocd/applicationset.yaml`; bootstrap and infrastructure charts are never managed by it, so a merge cannot restart a data service.

## Storage, backup and restore

Stateless: Argo CD's state is derived from this repository. Nothing to back up. A repository credential, when supplied, lives only in the `hl-helm-repo` Secret.

## Deviation from the constitution

None. Pins upstream chart `argo-cd` 10.10.5.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| argo-cd.applicationSet.resources.limits.memory | string | `"128Mi"` |  |
| argo-cd.applicationSet.resources.requests.cpu | string | `"20m"` |  |
| argo-cd.applicationSet.resources.requests.memory | string | `"64Mi"` |  |
| argo-cd.controller.resources.limits.memory | string | `"512Mi"` |  |
| argo-cd.controller.resources.requests.cpu | string | `"100m"` |  |
| argo-cd.controller.resources.requests.memory | string | `"256Mi"` |  |
| argo-cd.dex.enabled | bool | `false` |  |
| argo-cd.notifications.enabled | bool | `false` |  |
| argo-cd.redis.resources.limits.memory | string | `"128Mi"` |  |
| argo-cd.redis.resources.requests.cpu | string | `"20m"` |  |
| argo-cd.redis.resources.requests.memory | string | `"64Mi"` |  |
| argo-cd.redisSecretInit.resources.limits.memory | string | `"64Mi"` |  |
| argo-cd.redisSecretInit.resources.requests.cpu | string | `"10m"` |  |
| argo-cd.redisSecretInit.resources.requests.memory | string | `"32Mi"` |  |
| argo-cd.repoServer.resources.limits.memory | string | `"256Mi"` |  |
| argo-cd.repoServer.resources.requests.cpu | string | `"20m"` |  |
| argo-cd.repoServer.resources.requests.memory | string | `"128Mi"` |  |
| argo-cd.server.resources.limits.memory | string | `"256Mi"` |  |
| argo-cd.server.resources.requests.cpu | string | `"20m"` |  |
| argo-cd.server.resources.requests.memory | string | `"64Mi"` |  |
