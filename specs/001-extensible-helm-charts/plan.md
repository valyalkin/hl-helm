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
releases, and an application tier (React frontend, Kotlin/Spring Boot backend) that references its
dependencies rather than containing them.

Argo CD reconciles everything from Git via an app-of-apps root, with tiers expressed as sync
waves. One bootstrap command installs Argo CD; everything else, Argo CD's own configuration
included, follows from the repository. Onboarding a new service means copying a scaffold from
`scaffolds/`, changing a handful of marked parameters, and adding one Application manifest.

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
no plaintext secrets, scaffolds still render)

**Target Platform**: Single-node k3s on Linux (`alex-ThinkCentre-M710q`), x86-64, with k3s built-in
Traefik ingress and local-path storage. Exact k3s version to be recorded at quickstart step 0 once
cluster access is available (research R-010)

**Project Type**: Infrastructure-as-code repository — Helm charts plus Argo CD manifests. No
application source code is produced by this feature

**Performance Goals**: Cold rebuild of an empty node to a fully running cluster within 2 hours
(SC-005); pilot stack serving a browser-to-database round trip within 15 minutes of deploy start
(SC-020); merged change reaching the cluster within 10 minutes (SC-014)

**Constraints**: Single node with no staging cluster, so rendering plus schema validation is the
only pre-production gate; memory limits mandatory on every workload; no component in the bootstrap
tier may read a secret from Vault; unseal material never enters the repository

**Scale/Scope**: ~12 charts (1 library, 3 scaffolds, 2 bootstrap, 4 infrastructure, 2 application),
one cluster, one operator, low single-digit requests per second

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|-----------|------|--------|
| I. Declarative IaC | Every cluster resource originates from a chart in this repo | **PASS** — Argo CD reconciles all tiers; the only imperative act is the single bootstrap command, itself a checked-in script applying a checked-in values file |
| II. Chart-per-workload, shared library | One purpose per chart; boilerplate in a library chart | **PASS** — `charts/library/hl-common` holds all shared templates; each workload is its own chart; the app-of-apps root composes without embedding |
| III. Validate before apply | lint → template → schema-validate → diff, with `values.schema.json` per chart | **PASS** — CI runs all four; Argo CD diff is reviewable pre-merge and the agent itself previews before sync |
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
    ├── frontend/                   # React, runtime-injected backend address
    └── backend/                    # Kotlin/Spring Boot, Vault-sourced DB credentials

scaffolds/                          # Copy-paste starting points (FR-040)
├── stateless-web/                  # Static content shape
├── service-with-deps/              # Service + dependency references shape
└── stateful-service/               # Durable storage shape

argocd/
├── root.yaml                       # App-of-apps entry point
└── applications/                   # One Application per chart, tier → sync wave
    ├── bootstrap/
    ├── infrastructure/
    └── apps/

bootstrap/
├── install.sh                      # THE single manual command (FR-052)
└── argocd-values.yaml              # Values for the one-shot Argo CD install

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
runtime. `scaffolds/` is deliberately separate from `charts/` so that copy-paste sources are never
mistaken for deployed charts and never acquire a live Argo CD Application. `argocd/` holds the
app-of-apps manifests separately from the charts they point at, so that what is deployed and what
deploys it remain independently reviewable.

## Complexity Tracking

> Principle VII requires every added controller to be justified.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| Argo CD controller | FR-030–FR-035 require continuous reconciliation and automatic drift correction; the operator chose it explicitly | Operator-run `helm upgrade` from a tagged commit was considered and chosen against by the operator in specification; it detects drift but never corrects it |
| Vault + Vault Secrets Operator (2 controllers) | FR-026–FR-029 require secrets that are never committed, rotate without chart changes, and restart consumers that cannot reload. The operator chose Vault explicitly | SOPS-encrypted files need no controller but cannot rotate without a commit; External Secrets Operator is one controller instead of two but adds an abstraction layer over a single backend, and VSO's `rolloutRestartTargets` satisfies FR-019 directly |
| CloudNativePG operator | Postgres is the system of record. CNPG owns failover, PVC lifecycle, and point-in-time recovery primitives that FR-014 and FR-059 would otherwise place on hand-written templates | A plain StatefulSet from `hl-common` is fewer moving parts but puts data durability and recovery on us — the one place in a homelab where losing the gamble is unrecoverable. Bitnami's chart is excluded outright (research R-002) |
| First-party library chart rather than adopting `bjw-s/common` | FR-002 and FR-005 require *our* conventions enforced centrally, and SC-019's 20-line budget depends on defaults we choose | `bjw-s/common` is mature and homelab-proven, but adopting it makes the foundation a wrapper around someone else's defaults; see research R-001 for the reversal path if our library outgrows its usefulness |

Net: four controllers, three of them direct consequences of operator decisions recorded in the
specification. The fourth (CNPG) is the only discretionary one, and it protects the single
irreplaceable asset in the cluster.
