# Contract: `hl-common` Library Chart Interface

**Feature**: 001-extensible-helm-charts | **Date**: 2026-10-16

The public interface of the shared foundation. A consuming chart calls these named templates and
supplies values; it writes no Kubernetes resource boilerplate of its own. Changing any signature
here is a breaking change to every chart (major version bump, migration note per Governance).

## Entry points

| Template | Renders | Notes |
|----------|---------|-------|
| `hl-common.all` | Every resource one service needs | One line per service, called with that service's values block |
| `hl-common.workload` | Deployment or StatefulSet | Chosen by `.Values.workload.kind` |
| `hl-common.service` | Service | Ports from `.Values.service.ports` |
| `hl-common.ingress` | Ingress | TLS stanza always emitted (R-008) |
| `hl-common.secrets` | `VaultStaticSecret` per secret reference | Plus rollout-restart wiring |
| `hl-common.config` | ConfigMap from `config.values` and `config.files` | Content hashed onto the pod template unless `restartOnChange: false` |
| `hl-common.pvc` | PersistentVolumeClaim | Only when `.Values.storage.enabled` |
| `hl-common.serviceaccount` | ServiceAccount | Plus the VSO `VaultAuth` binding |
| `hl-common.namespace` | Namespace, ServiceAccount and `VaultAuth` for one application | Called once per application chart, from `templates/namespace.yaml` |

## Helpers available to extending charts

| Template | Returns | Purpose |
|----------|---------|---------|
| `hl-common.name` | Release-scoped resource name | So custom resources match foundation naming |
| `hl-common.labels` | Full standard label set | Applied to custom resources (FR-002) |
| `hl-common.selectorLabels` | Selector subset | Never includes version labels |
| `hl-common.image` | Fully-qualified image reference | Applies registry/owner defaults, rejects mutable tags |
| `hl-common.podSpec` | A complete pod spec | For custom controllers (CronJob, Job) that need the standard container |
| `hl-common.secretEnv` | `env` entries from secret references | For custom workloads |
| `hl-common.configHash` | Hash of rendered configuration | For custom controllers that must roll on config change |
| `hl-common.fail` | Render-time error | Used by charts to enforce their own required values |

## The extension contract (FR-003, FR-004)

A chart extends the foundation in exactly three sanctioned ways. Anything else is a signal the
foundation should change instead.

1. **Add a resource**: place an ordinary manifest in the chart's `templates/`, using
   `hl-common.name` and `hl-common.labels` so it carries shared conventions.
2. **Override a default**: set it in the chart's `values.yaml`. No template edit, no fork.
3. **Replace a rendered section**: define a template named `<chart>.override.<section>`; the
   library calls it in place of its own when present. Defining one requires a documented reason in
   the chart README (FR-004).

**Prohibited**: copying a template out of `hl-common` into a chart. CI policy check 2 treats a
chart-local copy of a library template as a failure, because a copy stops receiving convention
changes — exactly the drift the library exists to prevent.

## Guarantees

The foundation guarantees that every rendered workload carries, without the chart asking:

- A `requests.cpu`, `requests.memory`, and `limits.memory` value — rendering fails if memory is
  unset, since no safe default exists on a shared node
- Liveness and readiness probes
- The standard label set and a release-scoped name under 63 characters
- An image reference resolved against `ghcr.io/<owner>` and rejected if it resolves to a mutable
  tag
- `automountServiceAccountToken: false` unless the workload declares it needs the token
- A security context with a non-root user and a read-only root filesystem, overridable per chart
  with a documented reason
- A restart when its configuration changes, unless the chart opts out with a documented reason

## Versioning

`hl-common` follows SemVer independently of the charts consuming it. Consumers pin a minor range.
A change to any signature or guarantee above is MAJOR; a new optional value is MINOR; a rendering
fix that leaves output equivalent is PATCH. `helm unittest` snapshots pin the rendered output of
each entry point, so an unintended change to twelve charts fails CI rather than reaching the
cluster.
