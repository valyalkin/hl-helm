# Contract: Argo CD Application Manifests

**Feature**: 001-extensible-helm-charts | **Date**: 2026-10-16

How an **application** chart becomes a deployed release. One `Application` per chart under
`argocd/applications/<chart>.yaml`, all discovered by the root app-of-apps.

**Scope**: Argo CD manages `charts/apps/` only. Bootstrap and infrastructure charts have no
Application and are installed by `bootstrap/install.sh`; an Application pointing at a chart
outside `charts/apps/` is a defect that CI rejects (research R-006).

## Required fields

| Field | Rule |
|-------|------|
| `metadata.name` | Matches the chart directory name |
| `metadata.annotations["argocd.argoproj.io/sync-wave"]` | Matches the chart's tier (data-model.md § Tier) |
| `spec.source.path` | Points at `charts/<tier>/<chart>` |
| `spec.source.targetRevision` | A tag or commit, never a branch, for application-tier charts |
| `spec.destination.namespace` | One namespace per chart; infrastructure never shares with applications |
| `spec.syncPolicy.automated.prune` | `true` for applications, `false` for stateful infrastructure |
| `spec.syncPolicy.automated.selfHeal` | `true` everywhere — this is FR-031's drift correction |

## Rules

- **Prune is off for stateful infrastructure.** An accidental prune of Postgres or Vault is
  unrecoverable; drift there is reported and corrected by hand. This is the one deliberate gap in
  FR-031's automatic correction, and it is a considered trade of automation against data loss.
- **Tier directory and sync wave must agree** (FR-054). CI policy check 4 enforces it; a manifest
  in `applications/apps/` carrying an infrastructure wave fails the build.
- **No Application may reference a chart outside this repository.** Upstream charts are consumed
  through a wrapper chart's `Chart.yaml` dependencies, so the pinned version is visible in a diff.
- **Adding a service means adding exactly one manifest here** (FR-045). If onboarding requires
  touching anything else under `argocd/`, the app-of-apps root is wrong.

## Health and readiness

Argo CD's reported health is the operator's single view of FR-034 (does the cluster match the
repository, and is each component healthy). Charts must therefore render workloads whose
readiness genuinely reflects serviceability — a workload reporting ready while its database is
unreachable breaks the only status surface the operator has.
