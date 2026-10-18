# cloudnative-pg

CloudNativePG operator wrapper chart. The database itself is the separate `postgres` chart, so either can be redeployed without the other (FR-070).

## Storage, backup and restore

Stateless; it holds no data. Database volumes belong to the `postgres` chart.

## Deviation from the constitution

None. Pins upstream chart `cloudnative-pg` 0.29.1. Justified in the plan's Complexity Tracking: Postgres is the one irreplaceable asset.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cloudnative-pg.resources.limits.memory | string | `"256Mi"` |  |
| cloudnative-pg.resources.requests.cpu | string | `"50m"` |  |
| cloudnative-pg.resources.requests.memory | string | `"128Mi"` |  |
