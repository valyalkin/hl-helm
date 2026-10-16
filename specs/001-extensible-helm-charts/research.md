# Phase 0 Research: Extensible Helm Charts

**Feature**: 001-extensible-helm-charts | **Date**: 2026-10-16

Each decision below resolves an unknown in the plan's Technical Context. Versions were verified
2026-10-16 and must be re-verified at implementation time if that date has aged.

---

## R-001: Build a first-party library chart rather than adopting an existing one

**Decision**: Write `charts/library/hl-common` as a Helm library chart (`type: library`),
modelled on the two-tier pattern that `bjw-s/common` popularised: named templates returning whole
resources, consumed by thin application charts that supply only values.

**Rationale**: FR-002 and FR-005 require that *our* conventions — ghcr.io as the default registry,
mandatory memory limits, TLS ingress always on, Vault references rather than inline secrets — are
enforced centrally and changed in one place. Adopting an upstream library would make the
foundation a configuration of someone else's defaults, and SC-019's 20-line-per-chart budget
depends on choosing defaults that match this homelab rather than overriding defaults that do not.
A first-party library also keeps the onboarding guide (FR-039) describing our parameters instead
of delegating to upstream documentation.

**Alternatives considered**:
- `bjw-s/common` + `app-template`: mature, actively maintained, purpose-built for homelabs. Its
  surface is considerably larger than three pilot charts need, and its schema would become the
  scaffold's vocabulary. Rejected for ownership of defaults, not for quality — it remains the
  fallback if `hl-common` grows past roughly 400 lines of template without earning it.
- No library chart, conventions by copy-paste: directly violates Principle II and FR-003.
- A chart generator producing full charts: generated charts stop receiving convention changes,
  which is the drift FR-041 exists to prevent.

**Risk**: A first-party library is a maintenance commitment. Mitigated by keeping it small and by
`helm unittest` suites that pin its rendering behaviour.

---

## R-002: Exclude Bitnami charts and images entirely

**Decision**: Use no Bitnami chart or image anywhere in the repository.

**Rationale**: Effective 28 August 2025 Bitnami moved its public catalog to a legacy repository
(`docker.io/bitnamilegacy`) that receives no updates, and moved maintained, versioned images into
the paid Bitnami Secure Images offering. The packaged charts at `docker.io/bitnamicharts` stopped
receiving updates. For a homelab that pins explicit versions (FR-012, FR-058), depending on a
catalog whose versioned tags have been archived means pinning to images that will never receive a
security update. This is the single most consequential dependency decision in the plan, because
Bitnami's Postgres and Redis charts are the conventional default and would otherwise have been the
obvious picks.

**Alternatives considered**:
- Bitnami Secure Images subscription: cost is unjustifiable for a homelab.
- `bitnamilegacy` images pinned forever: knowingly adopting unpatched images for a database.

---

## R-003: Postgres via CloudNativePG, not a hand-written StatefulSet

**Decision**: Install the CloudNativePG operator (chart `cloudnative-pg` 0.29.1, operator 1.30.1)
as an infrastructure-tier chart, and define the database itself as a `Cluster` custom resource in
a separate first-party chart `charts/infrastructure/postgres`.

**Rationale**: Postgres is the only irreplaceable asset in the cluster. CNPG owns PVC lifecycle,
failover, in-place major-version handling, and the backup and point-in-time-recovery primitives
that FR-059's "state backup and restore expectations" will need when backups come into scope.
Writing these by hand in `hl-common` would place data durability on template logic. Splitting the
operator from the `Cluster` resource into two charts also satisfies FR-060 and FR-064: the
database's own release can be deleted and recreated without touching the operator, and its PVC
survives both.

**Alternatives considered**:
- A StatefulSet rendered by `hl-common`: fewer moving parts and better aligned with Principle VII,
  but recovery, failover, and PITR become our problem. Rejected — see Complexity Tracking.
- Zalando postgres-operator: comparable capability, smaller current community momentum.
- Postgres outside the cluster on the host: contradicts FR-055's prohibition on manual setup.

**Consequence**: CNPG CRDs must exist before the `postgres` chart renders successfully, which the
sync-wave ordering in R-006 handles.

---

## R-004: Vault standalone with file storage; Vault Secrets Operator for delivery

**Decision**: Vault from chart `vault` 0.34.1 (app 2.0.4) in standalone mode with file storage on
a retained PVC, in the bootstrap tier. Secret delivery via Vault Secrets Operator (chart
`vault-secrets-operator` 1.6.0) in the infrastructure tier, using `VaultStaticSecret` resources
that materialise Kubernetes Secrets and `rolloutRestartTargets` to restart consumers on rotation.

**Rationale**: VSO's `rolloutRestartTargets` satisfies FR-028 (a rotated secret reaches consumers,
restarting those that cannot reload) declaratively, with no sidecar injection and no application
awareness of Vault. Standalone file storage is the right size for one node; Raft or Consul would
add a cluster to maintain for no availability gain on single hardware.

**Alternatives considered**:
- External Secrets Operator: CNCF, multi-backend, one controller instead of two. Rejected on
  Principle VII grounds — it is an abstraction over backends when there is exactly one backend —
  but it is the natural migration if a second secret source ever appears.
- Vault Agent Injector: sidecar per pod, more runtime coupling, no declarative rollout restart.
- Vault CSI provider: mounts secrets as files; rotation handling is weaker.

**Licensing note**: Vault is BUSL-licensed since 2023. Homelab use is non-competing and therefore
permitted. OpenBao is the OSS fork and a drop-in migration path if that ever changes; charts
should reference Vault through values rather than hard-coding its service name, so the swap is a
values change.

**Bootstrap consequence**: Vault is in the bootstrap tier and FR-050 forbids it from consuming a
secret from the store. Satisfied — Vault's own chart needs no Vault secret. Its unseal keys and
root token are produced by `vault operator init` during bootstrap and stored by the operator
outside the cluster (FR-053). A node restart leaves Vault sealed; manual unseal is accepted
(spec assumption), and already-running workloads are unaffected because their Kubernetes Secrets
persist.

---

## R-005: Redis from the official image via a first-party chart

**Decision**: Deploy Redis 8 (`redis:8-alpine`, pinned by digest) using a first-party chart built
on `hl-common`, with no persistence.

**Rationale**: Bitnami is excluded (R-002), and Redis here is an accelerator rather than a system
of record (FR-078), so none of the HA, Sentinel, or operator-based options earn their complexity.
Deploying it from `hl-common` is also the cleanest proof that the library handles an
infrastructure workload, not only applications — directly exercising FR-057's requirement that new
infrastructure follows the same scaffold path. Redis 8 returned to an OSI-approved licence
(AGPLv3) in 2025, so there is no licensing obstacle.

**Alternatives considered**:
- Valkey (Linux Foundation fork) via a Cloudpirates chart: equally viable and licence-unambiguous;
  Redis was named explicitly in the specification, and the two are drop-in compatible, so this
  stays the fallback.
- DandyDeveloper `redis-ha`, OpsTree or Spotahome operators: built for failover this cluster
  cannot provide on one node.

---

## R-006: Tiers as Argo CD sync waves under an app-of-apps root

**Decision**: A root `Application` at `argocd/root.yaml` points at `argocd/applications/`, which
holds one `Application` per chart. Tier membership is expressed as
`argocd.argoproj.io/sync-wave`: bootstrap `-10` (Argo CD) and `-5` (Vault), infrastructure `0`
(VSO, CNPG operator) and `5` (Postgres cluster, Redis), applications `10` (backend) and `15`
(frontend). Directory position under `argocd/applications/<tier>/` must agree with the wave, and
CI checks that it does (FR-054).

**Rationale**: Sync waves give FR-013's ordering without coupling chart lifecycles, and the
app-of-apps root means adding a service is one new Application manifest (FR-045). Waves order the
*initial* convergence; FR-067 separately requires applications to tolerate missing dependencies at
runtime, so ordering is an optimisation rather than a correctness guarantee — which is what keeps
Argo CD from becoming a dependency manager.

**Alternatives considered**:
- ApplicationSet with a directory generator: less boilerplate per service, but per-chart overrides
  become generator templating, which is harder to read than one explicit manifest per chart.
  Reconsider once there are more than roughly fifteen charts.
- Helm subchart dependencies for ordering: couples lifecycles and is explicitly forbidden by
  FR-060.
- Argo CD sync phases/hooks: for jobs within a sync, not for tiering across applications.

---

## R-007: Bootstrap is one command that installs Argo CD and then steps aside

**Decision**: `bootstrap/install.sh` performs exactly one imperative action — `helm install argocd`
from the pinned chart with `bootstrap/argocd-values.yaml` — then applies `argocd/root.yaml`. Argo
CD thereafter manages its own release from `charts/bootstrap/argocd`, so the imperative install is
superseded by the declarative one on first reconcile.

**Rationale**: FR-052 permits exactly one manual command. Having Argo CD adopt its own release
afterwards satisfies FR-051 and Principle I without a second bootstrap step.

**Repository access**: Argo CD needs to read this Git repository, and that credential cannot come
from Vault — Vault is not running yet, and FR-050 forbids the dependency. The repository is
public, so anonymous read suffices and no credential is required for Argo CD to converge.

`bootstrap/install.sh` nonetheless accepts a repository credential as an argument, supplied by the
operator at invocation:

```bash
./bootstrap/install.sh --repo-credential <token-or-key-path>
```

When given, it is written directly into the Argo CD repository Secret and never persisted
anywhere else. It is never committed, never read from Vault, and never defaulted. This keeps the
one-command guarantee (FR-052) intact while covering three cases the public-read path does not:
making the repository private later, Argo CD writing back to Git (image-tag automation), and
hitting GitHub's anonymous API rate limits during a rebuild that syncs many applications at once.

**Tier rule preserved**: the credential enters as a bootstrap argument, not as a Vault reference,
so no bootstrap-tier component depends on the secret store (FR-050).

**Unresolved risk**: Argo CD adopting a release created by a direct `helm install` can produce a
first-sync diff on ownership metadata. Mitigation is to install with the same release name and
namespace the Application declares, and to verify an empty diff as a bootstrap acceptance step
(quickstart step 4).

---

## R-008: TLS from Traefik's default certificate; cert-manager deferred

**Decision**: `hl-common` always emits a `tls:` stanza on ingress with a configurable
`secretName`. With no issuer installed, Traefik serves its built-in self-signed certificate.

**Rationale**: FR-001 requires TLS-enabled ingress while the specification defers certificate
issuance — the two meet here. Because the template always emits the stanza and only the
`secretName` varies, introducing cert-manager later is a values change in each chart, not a
template change, which keeps Principle IV intact.

**Alternatives considered**:
- Install cert-manager now: out of declared scope, and a real issuer needs DNS or a public
  endpoint this homelab may not have.
- Plain HTTP until certificates exist: contradicts FR-001 and makes TLS a retrofit across every
  chart.

---

## R-009: Validation toolchain

**Decision**: `helm lint` → `helm template` across each chart's `ci/` values files → `helm
unittest` for `hl-common` logic → `kubeconform` against the cluster's Kubernetes version (with
CNPG, VSO, and Argo CD CRD schemas supplied) → first-party Python policy checks → `helm-docs` with
a dirty-tree check. All run in one GitHub Actions workflow; any failure blocks merge (FR-016).

**Rationale**: FR-008 requires a `values.schema.json` per chart, which catches type and range
errors at render time; `kubeconform` catches what the schema cannot, namely invalid Kubernetes
objects. `helm unittest` is what makes the library chart safe to change — it pins the rendered
output of each named template so a convention change cannot silently alter twelve charts.

**Policy checks are first-party Python** rather than conftest/OPA, because there are four rules and
adding a policy engine for four rules fails Principle VII:
1. No image reference resolves to a mutable tag (FR-021, SC-008).
2. No chart under `charts/apps/` declares a dependency on an infrastructure chart (FR-060, SC-033).
3. No file contains secret-shaped material (FR-020, SC-007).
4. Every scaffold still renders and validates against the current `hl-common` (FR-047, SC-026),
   and each `argocd/applications/<tier>/` entry's sync wave matches its tier (FR-054).

**Alternatives considered**: `chart-testing` (`ct`) with a kind cluster — valuable, but installing
charts into kind cannot validate against the real CRDs and node topology, and CNPG plus Vault in
CI is a slow and fragile way to learn less than `kubeconform` tells us immediately.

---

## R-010: Kubernetes version baseline

**Decision**: Target the k3s version currently on the node, recorded in the root `README.md` and
referenced by `kubeconform`'s `--kubernetes-version` flag, so validation and the cluster never
drift apart.

**Status**: **Unverified, resolvable.** The node's k3s version was not available when this plan
was written, and no kubeconfig was present on the workstation. Cluster access is being arranged;
once a kubeconfig exists, step 0 of [quickstart.md](./quickstart.md) settles this in one command
and the value is recorded in the root `README.md`.

The plan assumes Kubernetes 1.31 or later, which all four upstream charts support. If the node is
older, CloudNativePG 1.30's minimum is the binding constraint and must be checked before anything
else. Three other facts should be captured in the same pass, because each can invalidate a design
assumption:

| Check | Why it matters |
|-------|----------------|
| `kubectl get storageclass` | The plan assumes `local-path` is present and is the only class; charts name it explicitly rather than relying on the default |
| `kubectl get pods -A \| grep -iE 'traefik\|servicelb'` | R-008's TLS decision assumes k3s ships Traefik and it has not been disabled |
| `kubectl get pods -A \| grep -iE 'vault\|postgres'` | Confirms where the existing instances run before they are cleared, so nothing is deleted blind |

**Rationale**: Principle III's schema validation is only meaningful against the version actually
running, and the Platform Constraints section of the constitution requires the version to be
recorded in the README.
