# Implementation Plan: Extensible Helm Charts for Homelab Applications and Infrastructure

**Branch**: `001-extensible-helm-charts` | **Date**: 2026-10-16 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-extensible-helm-charts/spec.md`

## Summary

Build a Helm repository that is the single source of truth for a single-node k3s homelab. A small
library chart (`hl-common`) owns every shared convention — naming, labels, probes, resource
limits, TLS ingress, ghcr.io image defaults, Vault secret references — so that an individual chart
contains only what is unique to its workload. Three tiers of charts sit on top of it: a bootstrap
tier (Argo CD, Vault) that depends on nothing inside the cluster, an infrastructure tier
(Vault Secrets Operator, CloudNativePG, a Postgres cluster, Redis) deployed as independent
releases, and an application tier holding a single nginx reference chart. No business
application is in scope: the deliverable is a repository whose dependencies are running and whose
charts are ready to be extended with real services.

One bootstrap command installs the bootstrap and infrastructure tiers in dependency order from
pinned charts, then installs Argo CD. **Argo CD manages the application tier only** — a merge to
`main` deploys an application, while an infrastructure change reaches the cluster only through an
explicit `helm upgrade`, so no merge can restart a data service on its own. Onboarding a new
service means copying the nginx reference chart, changing a handful of marked parameters, and
adding one Application manifest.

## Technical Context

**Language/Version**: Helm 3.16+ templates (Go text/template + Sprig); Bash for the single
bootstrap script; Python 3.11 for repository policy checks in CI

**Primary Dependencies**:
- Argo CD — chart `argo-cd` 10.10.5 (app v3.5.5), repo `https://argoproj.github.io/argo-helm`
- Vault — chart `vault` 0.34.1 (app 2.0.4), repo `https://helm.releases.hashicorp.com`
- Vault Secrets Operator — chart `vault-secrets-operator` 1.6.0, same repo
- CloudNativePG — chart `cloudnative-pg` 0.29.1 (operator 1.30.1), repo
  `https://cloudnative-pg.github.io/charts`
- Redis — official `redis:8-alpine` image deployed by a first-party chart (no upstream chart)
- Bitnami charts are excluded; see [research.md](./research.md) decision R-002

**Storage**: k3s `local-path` provisioner. Postgres via a CloudNativePG `Cluster` with a retained
PVC; Vault in standalone mode with file storage on a retained PVC; Redis ephemeral by design

**Testing**: `helm lint`, `helm template`, `helm unittest` for library-chart template logic,
`kubeconform` for rendered-manifest schema validation, `helm-docs` for README generation and
drift detection, plus first-party Python policy checks (no `:latest`, no embedded dependencies,
no plaintext secrets, reference chart still renders)

**Target Platform**: Single-node k3s on Linux (`alex-ThinkCentre-M710q`), x86-64, with k3s built-in
Traefik ingress and local-path storage. Exact k3s version to be recorded at quickstart step 0 once
cluster access is available (research R-010)

**Project Type**: Infrastructure-as-code repository — Helm charts plus Argo CD manifests. No
application source code is produced by this feature

**Performance Goals**: Cold rebuild of an empty node to a fully running cluster within 2 hours
(SC-005); reference service reachable with database and cache healthy within 15 minutes of
deploy start (SC-020); merged change reaching the cluster within 10 minutes (SC-014)

**Constraints**: Single node with no staging cluster, so rendering plus schema validation is the
only pre-production gate; memory limits mandatory on every workload; no component in the bootstrap
tier may read a secret from Vault; unseal material never enters the repository

**Scale/Scope**: 8 charts (1 library, 2 bootstrap, 4 infrastructure, 1 reference application),
one cluster, one operator, low single-digit requests per second

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Declarative IaC | Every cluster resource originates from a chart in this repo | **PASS** — every component is a pinned chart here. Argo CD reconciles the application tier; infrastructure is applied by a checked-in script from checked-in values. The source of truth is unchanged; only the applying mechanism differs by tier |
| II. Chart-per-workload, shared library | One purpose per chart; boilerplate in a library chart | **PASS** — `charts/library/hl-common` holds all shared templates; each workload is its own chart; the app-of-apps root composes without embedding |
| III. Validate before apply | lint → template → schema-validate → diff, with `values.schema.json` per chart; human review gated per apply mechanism | **PASS** — CI runs all four. The application tier is reviewed at merge via a CI-rendered diff; infrastructure is reviewed with `helm diff upgrade` immediately before applying. Both gates are now explicit in Principle III (constitution v2.0.0) |
| IV. Environment parity through values | No environment-keyed branching in templates | **PASS** — single environment today; the library takes no environment parameter, and per-context differences live in values files only |
| V. Secrets never plaintext | No secret material committed, ever | **PASS** — Vault + VSO; charts carry `VaultStaticSecret` references only; CI scans for secret material; unseal keys stored outside the cluster by the operator |
| VI. Idempotent, reversible releases | Re-apply is a no-op; SemVer per chart; data outlives releases | **PASS** — CNPG PVC and Vault PVC are retained independently of release lifecycle; `helm unittest` asserts render stability; chart versions bumped per change |
| VII. Homelab simplicity (YAGNI) | Prefer k3s built-ins; justify every operator | **PARTIAL** — four controllers are introduced (Argo CD, Vault, VSO, CNPG). Each is justified in Complexity Tracking below; three of the four are operator-mandated choices |

**Platform constraints check**: k3s built-in Traefik and local-path are used rather than installing
an ingress controller or storage provisioner (Principle VII). Every workload declares requests and
memory limits, liveness and readiness probes, an explicit `storageClassName` where stateful, and a
digest- or tag-pinned image — all enforced by `hl-common` defaults and verified by CI policy
checks, so compliance is structural rather than per-chart discipline.

**Post-Phase 1 re-check**: **PASS**. The Phase 1 design introduces no further components. The
library-chart interface in [contracts/](./contracts/) makes Principle II's "no copied boilerplate"
and the Platform Constraints checklist properties of the foundation rather than obligations on
each chart author, which strengthens rather than weakens the gates.

## Project Structure

### Documentation (this feature)

```text
specs/001-extensible-helm-charts/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── library-chart-interface.md
│   ├── values-contract.md
│   └── argocd-application-contract.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Created by /speckit-tasks, not by this command
```

### Source Code (repository root)

```text
charts/
├── library/
│   └── hl-common/                  # The shared foundation (type: library)
│       ├── Chart.yaml
│       ├── values.yaml             # Documented defaults, no resources of its own
│       └── templates/
│           ├── _workload.tpl       # Deployment / StatefulSet
│           ├── _service.tpl
│           ├── _ingress.tpl        # TLS always on
│           ├── _probes.tpl
│           ├── _resources.tpl      # Memory limit mandatory
│           ├── _image.tpl          # ghcr.io/<owner> default registry
│           ├── _secrets.tpl        # VaultStaticSecret + rollout restart wiring
│           ├── _config.tpl          # ConfigMap from values or verbatim files, restart-on-change
│           ├── _storage.tpl        # Explicit storageClassName, retained claims
│           ├── _naming.tpl         # Names, labels, selectors
│           └── _validate.tpl       # fail() on unset required values
├── bootstrap/                      # Tier 0 — no dependency on Vault
│   ├── argocd/                     # Wraps argo-cd 10.10.5
│   └── vault/                      # Wraps vault 0.34.1, standalone + file storage
├── infrastructure/                 # Tier 1 — may depend on tier 0
│   ├── vault-secrets-operator/     # Wraps vault-secrets-operator 1.6.0
│   ├── cloudnative-pg/             # Wraps cloudnative-pg 0.29.1 (the operator)
│   ├── postgres/                   # First-party: CNPG Cluster CR + VSO secret
│   └── redis/                      # First-party: redis:8-alpine via hl-common
└── apps/                           # Tier 2 — may depend on tiers 0 and 1
    └── nginx/                      # THE reference chart: a real service, and the copy source

argocd/
├── root.yaml                       # App-of-apps entry point — application tier only
└── applications/                   # One Application per chart under charts/apps/

bootstrap/
├── install.sh                      # THE single manual command (FR-052): infra, then Argo CD
├── install-order.yaml              # Pinned install order and values for bootstrap + infra
└── argocd-values.yaml              # Values for the Argo CD install

docs/
├── onboarding.md                   # The guide (FR-039–FR-048)
├── bootstrap.md                    # Rebuild from empty node, Vault init and unseal
└── tiers.md                        # What each tier may depend on

tests/
├── unit/                           # helm unittest suites for hl-common
└── policy/                         # Python checks: no :latest, no embedded deps, no secrets

.github/workflows/
└── ci.yaml                         # lint → template → unittest → kubeconform → policy → docs
```

**Structure Decision**: Charts are grouped by tier (`bootstrap/`, `infrastructure/`, `apps/`)
because the tier boundary is the feature's central invariant — FR-049 through FR-054 — and a
directory layout that mirrors it makes a violation visible in a diff rather than discoverable at
runtime. There is no `scaffolds/` directory: the copy source is `charts/apps/nginx/`, a real
deployed service. A template that is continuously rendered, validated, and running cannot
silently rot, whereas an inert scaffold directory can drift from the foundation unnoticed until
someone copies it. The tier boundary is now operational as well as organisational: everything
under `charts/apps/` is reconciled continuously by Argo CD, and everything above it is installed
and upgraded by `bootstrap/install.sh`, so `argocd/applications/` holds application charts only.

## Complexity Tracking

> Principle VII requires every added controller to be justified.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| Argo CD controller | FR-030, FR-031 require continuous reconciliation and automatic drift correction for the application tier | Operator-run `helm upgrade` is used for the infrastructure tiers instead, and is preferred there precisely because it cannot restart a data service without an explicit act |
| Vault + Vault Secrets Operator (2 controllers) | FR-026–FR-029 require secrets that are never committed, rotate without chart changes, and restart consumers that cannot reload. The operator chose Vault explicitly | SOPS-encrypted files need no controller but cannot rotate without a commit; External Secrets Operator is one controller instead of two but adds an abstraction layer over a single backend, and VSO's `rolloutRestartTargets` satisfies FR-019 directly |
| CloudNativePG operator | Postgres is the system of record. CNPG owns failover, PVC lifecycle, and point-in-time recovery primitives that FR-014 and FR-059 would otherwise place on hand-written templates | A plain StatefulSet from `hl-common` is fewer moving parts but puts data durability and recovery on us — the one place in a homelab where losing the gamble is unrecoverable. Bitnami's chart is excluded outright (research R-002) |
| First-party library chart rather than adopting `bjw-s/common` | FR-002 and FR-005 require *our* conventions enforced centrally, and SC-019's 20-line budget depends on defaults we choose | `bjw-s/common` is mature and homelab-proven, but adopting it makes the foundation a wrapper around someone else's defaults; see research R-001 for the reversal path if our library outgrows its usefulness |

Net: four controllers, three of them direct consequences of operator decisions recorded in the
specification. The fourth (CNPG) is the only discretionary one, and it protects the single
irreplaceable asset in the cluster.

### Resolved: constitution amended to v2.0.0

Two clauses written before Argo CD was chosen have been amended, so no conflict remains:

1. **Principle III** now ties the human review of a rendered diff to how a component is applied —
   at merge for continuously reconciled components, at `helm diff upgrade` for explicitly applied
   ones — and requires every component to have exactly one of those gates.
2. **Development Workflow** replaces the tagged-commit rule with a per-tier deployment rule, adds
   the infrastructure upgrade procedure, and records the drift caveat below as a standing
   obligation.

Accepted cost, now constitutionally recorded: infrastructure drift is not detected automatically.
Nothing watches Vault, Postgres or Redis for out-of-band change. The constitution requires the
rebuild procedure to be exercised on a disposable cluster regularly, because that exercise is the
only thing that proves the repository still matches reality.
