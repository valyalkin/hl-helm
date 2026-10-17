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
