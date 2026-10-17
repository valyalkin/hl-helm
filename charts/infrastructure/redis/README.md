# redis (infrastructure tier)

Redis 8 (`redis:8-alpine`, pinned by digest) built on `hl-common`. **No persistence**: this is an
accelerator, not a system of record, so a consumer should declare it `optional: true` and degrade
when it is absent (FR-082).

## Connection details for a consuming chart

| What | Value |
|------|-------|
| Address | `redis.redis.svc.cluster.local` |
| Port | `6379` |
| Credentials in Vault | `kv/infra/redis`, key `password` (readable by every application) |

```yaml
dependencies:
  redis:
    host: redis.redis.svc.cluster.local
    port: 6379
    optional: true
    credentials:
      vaultPath: infra/redis
      keys: {password: REDIS_PASSWORD}
```

The password is seeded by a pre-install Job only if absent, so a redeploy never changes it.

## Storage, backup and restore

None by design: data is discarded when the pod restarts. There is nothing to back up. Moving to a
persistent cache means adding `storage:` to the service block and is a deliberate change.

## Deviation from the constitution

None.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| provision.authMount | string | `"kubernetes"` |  |
| provision.enabled | bool | `true` |  |
| provision.entries[0].generate[0] | string | `"password"` |  |
| provision.entries[0].path | string | `"infra/redis"` |  |
| provision.image.digest | string | `"sha256:5be49781ecf78bfe775c5309c6a4d9f4e9e040b6c885c99eb2b12fb69855e1a2"` |  |
| provision.image.name | string | `"vault"` |  |
| provision.image.owner | string | `"hashicorp"` |  |
| provision.image.registry | string | `"docker.io"` |  |
| provision.image.tag | string | `"2.0.4"` |  |
| provision.kvMount | string | `"kv"` |  |
| provision.role | string | `"provision"` |  |
| provision.vaultAddr | string | `"http://vault.vault.svc.cluster.local:8200"` |  |
| redis.secrets.auth.keys.password | string | `"REDIS_PASSWORD"` |  |
| redis.secrets.auth.vaultPath | string | `"infra/redis"` |  |
| redis.service.ports[0].name | string | `"redis"` |  |
| redis.service.ports[0].port | int | `6379` |  |
| redis.workload.command[0] | string | `"sh"` |  |
| redis.workload.command[1] | string | `"-c"` |  |
| redis.workload.command[2] | string | `"exec redis-server --save \"\" --appendonly no --requirepass \"$REDIS_PASSWORD\""` |  |
| redis.workload.image.digest | string | `"sha256:3811787313eba226a2ef38658c6ccb91cd5e110edc89c37767de373120a0e5a0"` |  |
| redis.workload.image.name | string | `"redis"` |  |
| redis.workload.image.owner | string | `"library"` |  |
| redis.workload.image.registry | string | `"docker.io"` |  |
| redis.workload.image.tag | string | `"8-alpine"` |  |
| redis.workload.resources.limits.memory | string | `"128Mi"` |  |
| redis.workload.resources.requests.cpu | string | `"20m"` |  |
| redis.workload.resources.requests.memory | string | `"64Mi"` |  |
| redis.workload.tmpDirs[0] | string | `"/data"` |  |
| vaultAuth.createNamespace | bool | `false` |  |
| vaultAuth.role | string | `"infra"` |  |
