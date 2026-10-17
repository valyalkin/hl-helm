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
  surface is considerably larger than this delivery needs, and its schema would become the
  reference chart's vocabulary. Rejected for ownership of defaults, not for quality — it remains the
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
infrastructure follows the same copy-the-reference-chart path. Redis 8 returned to an OSI-approved licence
(AGPLv3) in 2025, so there is no licensing obstacle.

**Alternatives considered**:
- Valkey (Linux Foundation fork) via a Cloudpirates chart: equally viable and licence-unambiguous;
  Redis was named explicitly in the specification, and the two are drop-in compatible, so this
  stays the fallback.
- DandyDeveloper `redis-ha`, OpsTree or Spotahome operators: built for failover this cluster
  cannot provide on one node.

---

## R-006: Argo CD for the application tier only; a script for everything beneath it

**Decision**: Argo CD holds one `Application` per chart under `charts/apps/`, discovered by a
root app-of-apps at `argocd/root.yaml`, syncing automatically from `main` with `selfHeal: true`.
The bootstrap and infrastructure tiers are **not** in Argo CD. `bootstrap/install.sh` installs
them with `helm` in dependency order from an explicit, checked-in order file, then installs Argo
CD last.

**Rationale**: The operator's requirement is that a merge must never restart a data service on
its own. Keeping Vault, VSO, CloudNativePG, Postgres and Redis outside Argo CD makes that
structural rather than a policy that can be misconfigured — there is no controller that could
apply them. Dependency ordering, which sync waves would otherwise provide, becomes ordering in a
shell script, which is easier to read and debug than wave annotations spread across manifests.
It also removes three awkward problems: Argo CD managing the secret store it does not depend on,
CRD-ordering between the CNPG operator and the `Cluster` resource, and Argo CD adopting its own
imperatively installed release.

**Alternatives considered**:
- All tiers in Argo CD with sync waves, infrastructure on manual sync: keeps drift *detection*
  for infrastructure, which this design loses. Rejected by the operator in favour of the simpler
  boundary; the trade is recorded in the plan.
- All tiers auto-synced: a merge could restart Postgres. Rejected outright.
- ApplicationSet with a directory generator over `charts/apps/`: less boilerplate per service,
  worth reconsidering past roughly fifteen application charts.

**Accepted cost**: nothing watches the infrastructure tiers for out-of-band change. Drift there
is found by running the rebuild, not by a dashboard. FR-034 is narrowed accordingly, and the
mitigation is to exercise the rebuild procedure regularly rather than trust it.

---

## R-007: Bootstrap installs infrastructure, then hands the application tier to Argo CD

**Decision**: `bootstrap/install.sh` is the single manual command. It reads
`bootstrap/install-order.yaml` — a pinned list of chart paths and values files — and runs `helm
upgrade --install` for Vault, the Vault Secrets Operator, CloudNativePG, Postgres and Redis in
that order, waiting for each to be healthy. It then installs Argo CD from
`charts/bootstrap/argocd/` with `bootstrap/argocd-values.yaml` and applies `argocd/root.yaml`.

**Rationale**: FR-052 permits exactly one manual command, and this keeps that promise while
putting the infrastructure tiers outside continuous reconciliation. Because the same script and
the same pinned values are used for a rebuild and for day-to-day infrastructure upgrades, the
rebuild path is exercised by ordinary use rather than only in an emergency.

**Infrastructure upgrades** re-run the script, or a single chart from it, after reviewing `helm
diff upgrade`. That diff review is where Principle III's human gate lives for these tiers.

**Repository access**: Argo CD needs to read this Git repository. The repository is public, so
anonymous read suffices. `install.sh` accepts an optional `--repo-credential`, written straight
into the Argo CD repository Secret and persisted nowhere else, for a future private repository,
Git write-back, or anonymous rate limits during a cold rebuild. It is never committed and never
read from Vault, so no bootstrap-tier component depends on the secret store (FR-050).

**Resolved risk**: Argo CD no longer needs to adopt its own imperatively installed release — it
is installed by the script and is not managed by itself, which removes the first-sync ownership
diff that the previous design had to verify.

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
4. The reference chart still renders and validates against the current `hl-common` (FR-047, SC-026),
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

---

## R-011: Configuration as ConfigMap, with restart-on-change by default

**Decision**: `hl-common` renders a ConfigMap from two sources — structured values the chart
renders into the required format, and whole files carried verbatim from the chart's `files/`
directory. The ConfigMap's content is hashed into a pod-template annotation, so any configuration
change rolls the workload. A chart may set `config.restartOnChange: false` when its workload
reloads configuration without a restart, with the reason recorded in its README.

**Rationale**: Kubernetes updates a mounted ConfigMap in place but does not restart the consuming
pod, so a process that reads its configuration at startup silently keeps serving the old values.
Nothing appears broken, which makes it an expensive failure to diagnose. Hashing the content into
the pod template is the standard remedy and makes the restart a property of the foundation rather
than something each chart author must remember (FR-037).

Verbatim files matter because an `nginx.conf` escaped into YAML values is painful to read, diff
and edit; carrying the real file keeps the chart readable and lets the operator paste in upstream
configuration unchanged (FR-038).

**Alternatives considered**:
- Restart never, operator restarts manually: FR-037 requires the change to reach the workload,
  and relying on memory is exactly what the foundation exists to avoid.
- Restart always, no opt-out: simpler, but wrong for a workload that genuinely reloads — and
  actively undesirable for a database where a log-level change should not cause a bounce.
- A sidecar config reloader: another component to maintain, for a problem a hash annotation
  solves in three lines (Principle VII).
