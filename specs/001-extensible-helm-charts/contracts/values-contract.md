# Contract: Chart Values Surface

**Feature**: 001-extensible-helm-charts | **Date**: 2026-10-16

The values vocabulary every chart shares, enforced by a `values.schema.json` generated from the
library's schema fragments. Structures are specified in [data-model.md](../data-model.md); this
contract fixes the *shape* and the failure behaviour.

## Canonical shape

```yaml
workload:            # see data-model.md § Workload
  image: {name, tag|digest, registry?, owner?, pullSecret?}
  kind: Deployment|StatefulSet
  replicas: 1
  resources: {requests: {cpu, memory}, limits: {memory}}
  probes: {liveness, readiness, startup?}

service:
  ports: [{name, port, targetPort, protocol?}]

ingress:             # see data-model.md § Ingress
  enabled: false

storage:             # see data-model.md § Storage
  enabled: false

secrets:             # map of logical name → Secret reference
  {}

dependencies:        # map of logical name → Dependency reference
  {}
```

## Failure behaviour (FR-008, FR-043)

Validation fails at render time, before anything reaches the cluster, when:

| Condition | Message must name |
|-----------|-------------------|
| A required value is unset | The value's path |
| `resources.limits.memory` is unset | The value's path — there is no default |
| An image resolves to a mutable tag | The chart and the offending reference |
| A scaffold placeholder is unchanged | The placeholder's parameter |
| An ingress host collides with another chart's | Both charts |
| A bootstrap-tier chart declares `secrets` | The chart and the tier rule |
| A referenced Vault path is absent | The path (at sync time; render cannot know) |

Failures must be render-time wherever the information exists at render time. The last row is the
only case deferred to sync, because only the cluster can know what Vault holds.

## Compatibility rules

- Adding an optional value with a default is backward compatible.
- Making an optional value required, removing one, or changing its type is breaking: major bump on
  `hl-common` plus a migration note naming every affected chart (Governance).
- A chart may add values of its own under a top-level key named for the chart. It must not add
  keys to the shared namespaces above — those belong to the library.
