# Phase 1 Data Model: Extensible Helm Charts

**Feature**: 001-extensible-helm-charts | **Date**: 2026-10-16

The "entities" here are configuration structures, not persisted records. Each maps to a spec
entity and is expressed in Helm values, validated by `values.schema.json`, and consumed by
`hl-common` named templates.

---

## Chart

One deployable unit. Maps to spec entity *Application chart* / *Infrastructure chart*.

| Field | Type | Required | Rule |
|-------|------|----------|------|
| `name` | string | yes | DNS-1123 label, ≤ 53 chars so generated names stay under the 63-char limit |
| `version` | semver | yes | Bumped on any template or default change (FR-018, Principle VI) |
| `appVersion` | string | yes | Tracks the upstream component version |
| `tier` | enum | yes | `bootstrap` \| `infrastructure` \| `application` |
| `dependencies` | list | no | Library chart only. An `application`-tier chart MUST NOT depend on an `infrastructure`-tier chart (FR-060) |

**Validation**: `tier` must agree with the chart's directory and with its Argo CD sync wave
(FR-054). Enforced by policy check 4.

---

## Workload

The common shape every chart renders through `hl-common`. Maps to the shared foundation's input.

| Field | Type | Required | Default | Rule |
|-------|------|----------|---------|------|
| `image.name` | string | yes | — | Short name; registry and owner are prefixed by the library |
| `image.tag` | string | yes* | — | Mutable tags rejected (FR-021). `*` Either `tag` or `digest` |
| `image.digest` | string | no | — | Preferred over `tag` when present |
| `image.registry` | string | no | `ghcr.io` | Overridable for upstream components (FR-025) |
| `image.owner` | string | no | repo owner | Default namespace within the registry (FR-023) |
| `image.pullSecret` | secret ref | no | — | Name of a VSO-materialised secret, never a literal (FR-024) |
| `replicas` | int | no | `1` | ≥ 0 |
| `kind` | enum | no | `Deployment` | `Deployment` \| `StatefulSet`; `StatefulSet` required when `storage` is set |
| `resources.requests.cpu` | quantity | no | `10m` | Mandatory in output (Platform Constraints) |
| `resources.requests.memory` | quantity | yes | — | No safe default exists on a shared node |
| `resources.limits.memory` | quantity | yes | — | Mandatory; unbounded workloads can evict the cluster |
| `resources.limits.cpu` | quantity | no | unset | Deliberately unset — CPU limits cause throttling without protecting the node |
| `probes.liveness` | probe | yes | — | Required for long-running workloads |
| `probes.readiness` | probe | yes | — | Must fail while dependencies are unreachable (FR-067) |
| `probes.startup` | probe | no | — | Recommended for JVM workloads |

**State transitions**: a workload is *rendered* → *synced* → *progressing* → *healthy* or
*degraded*. Readiness governs the last step and is what FR-067 relies on.

---

## Ingress

| Field | Type | Required | Default | Rule |
|-------|------|----------|---------|------|
| `enabled` | bool | no | `false` | |
| `host` | string | yes when enabled | — | Must be unique across all charts; collisions fail at render time (hostname-collision edge case) |
| `path` | string | no | `/` | |
| `tls.secretName` | string | no | unset | Unset means Traefik's default certificate (R-008); the `tls:` stanza is always emitted |
| `port` | int | yes when enabled | — | Must match a declared service port |

**Validation**: hostname collisions across charts are a render-time failure, not a runtime
takeover.

---

## Storage

| Field | Type | Required | Default | Rule |
|-------|------|----------|---------|------|
| `enabled` | bool | no | `false` | |
| `size` | quantity | yes when enabled | — | |
| `storageClassName` | string | yes when enabled | — | Explicit; implicit default class is forbidden |
| `retain` | bool | no | `true` | Claim outlives the release (FR-074, Principle VI) |
| `mountPath` | string | yes when enabled | — | |

---

## Secret reference

Maps to spec entity *Secret reference*. Renders a VSO `VaultStaticSecret`, never a literal.

| Field | Type | Required | Rule |
|-------|------|----------|------|
| `vaultPath` | string | yes | Path in the KV mount |
| `keys` | map | yes | Vault key → environment variable or file name |
| `refreshAfter` | duration | no | Defaults to `1h`; bounds SC-016's one-hour rotation target |
| `rolloutRestart` | bool | no | Defaults to `true`; restarts the consuming workload on change (FR-028) |

**Validation**: a referenced path that does not resolve fails deployment visibly rather than
producing an empty credential (FR-027). No field may contain secret material (FR-020).

---

## Dependency reference

Maps to spec entity *Dependency reference*. How an application reaches infrastructure without
either side knowing the other's internals (FR-063).

| Field | Type | Required | Rule |
|-------|------|----------|------|
| `host` | string | yes | Stable in-cluster service address, supplied as configuration |
| `port` | int | yes | |
| `credentials` | secret ref | no | A Secret reference as above |
| `optional` | bool | no | Defaults to `false`. `true` means the consumer degrades rather than fails (Redis, FR-078) |

**Rule**: never assembled from another chart's release name or template helpers. A dependency's
address is an input, which is what makes the two lifecycles separable.

---

## Tier

Maps to spec entity *Tier*. Not a values field — a property of a chart's location and sync wave.

| Tier | May depend on | Applied by | Members |
|------|---------------|-----------|---------|
| `bootstrap` | nothing in-cluster | `bootstrap/install.sh` | Vault, then Argo CD last |
| `infrastructure` | bootstrap | `bootstrap/install.sh` | VSO, CNPG operator, Postgres, Redis |
| `application` | bootstrap, infrastructure | Argo CD, auto-sync from `main` | nginx reference chart; real services later |

**Invariants**: no bootstrap-tier chart may contain a Secret reference (FR-050) — the single rule
that keeps a cold rebuild from deadlocking. And only an application-tier chart may have an Argo
CD Application (FR-030); one pointing above `charts/apps/` is a defect. Both are checked in CI.

---

## Configuration

Maps to spec entity *Application configuration* (FR-036–FR-038). Rendered as a ConfigMap by
`hl-common`, with its content hashed into the pod template.

| Field | Type | Required | Default | Rule |
|-------|------|----------|---------|------|
| `values` | map | no | `{}` | Structured settings the chart renders into the required format |
| `files` | list | no | `[]` | Paths under the chart's `files/` carried verbatim into the ConfigMap |
| `mountPath` | string | yes when set | — | Where the ConfigMap is mounted |
| `restartOnChange` | bool | no | `true` | Rolls the workload when content changes; `false` requires a documented reason in the chart README |

**Validation**: a chart MUST NOT define the same key in both `values` and `files`. No
configuration may contain secret material — that belongs in a Secret reference (FR-020).

**State transition**: content change → new hash on the pod template → rolling restart, unless
`restartOnChange` is false, in which case the mounted file updates in place and the workload is
expected to notice on its own.

---

## Reference chart

Maps to the onboarding path (FR-040, FR-042). One chart, `charts/apps/nginx/`, serving as both a
running service and the thing an operator copies.

| Field | Type | Rule |
|-------|------|------|
| `parameters` | list | Each marked `# REQUIRED:` with purpose and example |
| `placeholders` | list | Sentinel values that MUST fail validation if left unchanged (FR-043) |

**Validation**: the reference chart renders, validates, and deploys on every change (FR-047), so
a foundation change that would invalidate a copy fails CI rather than an operator's afternoon.
Because it is a deployed workload rather than an inert template, staleness is caught by the
cluster as well as by CI.
