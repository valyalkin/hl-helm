# Contract: Argo CD ApplicationSet

**Feature**: 001-extensible-helm-charts | **Date**: 2026-10-16

How an **application** becomes a deployed release. A single ApplicationSet at
`argocd/applicationset.yaml` uses a directory generator over `charts/apps/*` and creates one
Application per application chart. There are no hand-written manifests.

**Scope**: Argo CD manages `charts/apps/` only. Bootstrap and infrastructure charts are installed
by `bootstrap/install.sh`; an Application pointing outside `charts/apps/` is a defect CI rejects
(research R-006).

## Path convention — the deployment configuration

```
charts/apps/<application>/
```

| Derived value | From | Example |
|---------------|------|---------|
| Namespace | the directory name | `charts/apps/todo` → `todo` |
| Application name | the directory name | → `todo` |

Adding an application is therefore adding a directory. Adding a service to an existing
application is a template and a values block inside that application's chart, and needs no
change here at all (FR-045).

## Generated Application fields

| Field | Rule |
|-------|------|
| `spec.source.path` | The discovered directory |
| `spec.source.targetRevision` | `main` — merging an application change deploys it |
| `spec.destination.namespace` | The first path segment |
| `spec.syncPolicy.automated.prune` | `true` — application-tier workloads are replaceable |
| `spec.syncPolicy.automated.selfHeal` | `true` — this is FR-037's drift correction |
| `spec.syncPolicy.syncOptions` | `CreateNamespace=false` — the application's own chart renders its Namespace, so one release owns it and deletion is deliberate |

## Rules

- **One namespace per application, never shared** (FR-039). Two applications in one namespace
  means a later network policy cannot separate them.
- **An application's chart renders its own namespace-scoped resources** — the Namespace, its
  ServiceAccount and its `VaultAuth`. Because one chart deploys the whole application, a single
  release owns them and no ownership conflict is possible.
- **No Application may reference a chart outside this repository.** Upstream charts are consumed
  through a wrapper chart's `Chart.yaml` dependencies, so the pinned version shows in a diff.
- **Infrastructure is excluded by construction**, not by policy: the generator only looks under
  `charts/apps/`.

## Health and readiness

Argo CD's reported health is the operator's view of FR-041 for the application tier. Charts must
render workloads whose readiness genuinely reflects serviceability — a workload reporting ready
while its database is unreachable breaks the only status surface there is. Infrastructure state
is not visible here and is reported by the documented command in `docs/tiers.md`.
