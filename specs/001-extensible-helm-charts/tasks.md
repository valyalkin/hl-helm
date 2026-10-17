---

description: "Task list for feature implementation"
---

# Tasks: Extensible Helm Charts for Homelab Applications and Infrastructure

**Input**: Design documents from `/specs/001-extensible-helm-charts/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included. The specification requires them explicitly — FR-016 (automated
checks block merge), FR-048 (scaffolds verified against the foundation), and SC-026. `helm
unittest` is also what makes the library chart safe to change, since one template edit reaches
every chart.

**Organization**: Tasks are grouped by user story so each can be implemented and tested
independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US7)

## Path Conventions

Repository root paths per plan.md: `charts/library/`, `charts/bootstrap/`,
`charts/infrastructure/`, `charts/apps/`, `argocd/`, `bootstrap/`, `docs/`, `tests/`, `scripts/`.
There is no `scaffolds/` directory — `charts/apps/nginx/` is the reference chart operators copy.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Workstation tooling and repository skeleton. Nothing here needs cluster access.

- [X] T001 [P] Install layer-0 tooling used by `scripts/validate.sh`: `brew install helm kubeconform helm-docs k3d` and `helm plugin install https://github.com/helm-unittest/helm-unittest`
- [X] T002 [P] Create root `.gitignore` covering `*.tgz`, `charts/**/charts/`, `.DS_Store`, and local kubeconfigs
- [X] T003 [P] Create root `README.md` with repository purpose, tier model, and a placeholder for the k3s version recorded in T005
- [X] T004 Create the directory skeleton from plan.md: `charts/{library,bootstrap,infrastructure,apps}/`, `argocd/`, `bootstrap/`, `docs/`, `tests/{unit,policy}/`, `scripts/`
- [ ] T005 Record the cluster baseline in `README.md` — k3s version, storage classes, Traefik presence — per quickstart step 0 (**requires kubeconfig; blocks T042 if below Kubernetes 1.31**)
- [ ] T006 [P] Create a disposable local cluster for iteration per quickstart layer 1: `k3d cluster create homelab-test --servers 1`
- [ ] T007 Create the public GitHub remote and push `main`, so Argo CD has a repository to read; record its URL in `argocd/applicationset.yaml` (research R-007)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The primitives every chart and every story depends on, plus enough validation to
develop against.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T008 Create `charts/library/hl-common/Chart.yaml` with `type: library`, name `hl-common`, version `0.1.0`
- [X] T009 Create `charts/library/hl-common/values.yaml` with the documented default surface from contracts/values-contract.md
- [X] T010 [P] Implement `charts/library/hl-common/templates/_naming.tpl` — `hl-common.name`, `hl-common.fullname` (truncated to 53 chars), `hl-common.labels`, `hl-common.selectorLabels`
- [X] T011 [P] Implement `charts/library/hl-common/templates/_validate.tpl` — `hl-common.fail` and required-value assertions that name the offending value path
- [X] T012 [P] Implement `charts/library/hl-common/templates/_image.tpl` — `hl-common.image` applying the `ghcr.io/<owner>` default, preferring digest over tag, failing on a mutable tag (FR-021, FR-023, FR-025)
- [X] T013 Create `scripts/validate.sh` with a minimal development gate: `helm lint` plus `helm template` over every chart (expanded to the full gate in US5)
- [X] T014 Create the `helm unittest` harness at `tests/unit/` with a passing smoke suite for `hl-common.name`
- [X] T015 [P] Write unit tests for naming, labels, and truncation in `tests/unit/naming_test.yaml`
- [X] T016 [P] Write unit tests for image resolution and mutable-tag rejection in `tests/unit/image_test.yaml`

**Checkpoint**: `scripts/validate.sh` passes and `helm unittest charts/library/hl-common` is green.

---

## Phase 3: User Story 1 — Deploy an application from a reusable chart foundation (P1) 🎯 MVP

**Goal**: A chart described by image, port, and hostname renders a complete, valid, deployable set
of resources with probes, limits, and TLS ingress from safe defaults.

**Independent Test**: Render the first consuming chart from a minimal values file and confirm the
output is a complete, valid set of cluster resources that deploys successfully.

- [X] T017 [P] [US1] Implement `charts/library/hl-common/templates/_resources.tpl` — requests always emitted, `limits.memory` mandatory with render failure when unset, `limits.cpu` deliberately unset
- [X] T018 [P] [US1] Implement `charts/library/hl-common/templates/_probes.tpl` — liveness and readiness required, optional startup probe
- [X] T019 [US1] Implement `charts/library/hl-common/templates/_workload.tpl` — Deployment or StatefulSet per `workload.kind`, with `automountServiceAccountToken: false` and a non-root, read-only-root-filesystem security context by default
- [X] T020 [P] [US1] Implement `charts/library/hl-common/templates/_service.tpl` from `service.ports`
- [X] T021 [P] [US1] Implement `charts/library/hl-common/templates/_ingress.tpl` — TLS stanza always emitted with a configurable `secretName` (research R-008)
- [X] T022 [P] [US1] Implement `charts/library/hl-common/templates/_serviceaccount.tpl`
- [X] T023 [P] [US1] Implement `charts/library/hl-common/templates/_config.tpl` — ConfigMap from `config.values` and verbatim `config.files`, content hashed onto the pod template, `restartOnChange` defaulting to true (FR-036, FR-037, FR-038, research R-011)
- [X] T024 [US1] Implement the `hl-common.all` entry point in `charts/library/hl-common/templates/_all.tpl`, composing every resource the values describe
- [X] T025 [US1] Create `charts/library/hl-common/values.schema.json` covering the shared values surface per contracts/values-contract.md
- [X] T026 [US1] Create the reference chart `charts/apps/nginx/` — one chart deploying one application: `Chart.yaml` depending on `hl-common`, a `values.yaml` of under 20 lines with one block per service using a digest-pinned `nginx:alpine`, and `templates/web.yaml` as a single call to `hl-common.all`
- [X] T027 [P] [US1] Create `charts/apps/nginx/ci/default-values.yaml` as the render test fixture
- [X] T028 [P] [US1] Write unit tests in `tests/unit/workload_test.yaml` asserting probes, resource limits, and security context appear without the chart requesting them
- [X] T029 [P] [US1] Write unit tests in `tests/unit/ingress_test.yaml` asserting the TLS stanza is always present
- [X] T030 [US1] Write a unit test in `tests/unit/required_values_test.yaml` asserting that an omitted required value fails rendering and names the value (US1 acceptance scenario 2)
- [ ] T031 [US1] Verify idempotence: install `charts/apps/nginx` to the k3d cluster, re-apply unchanged, confirm no diff (US1 acceptance scenario 4, FR-017)

**Checkpoint**: A new application deploys from image, port, and hostname alone. MVP reached.

---

## Phase 4: User Story 2 — Extend a chart beyond the defaults (P1)

**Goal**: A chart adds what is unique to it and still inherits every shared convention, with no
boilerplate copied.

**Independent Test**: Add a resource the foundation does not provide to a chart, confirm the output
carries it alongside foundation resources with matching naming and labels, and confirm a
convention change still reaches that chart.

- [ ] T032 [P] [US2] Implement `hl-common.podSpec` in `charts/library/hl-common/templates/_podspec.tpl`, exposing a complete pod spec for custom controllers such as CronJob
- [ ] T033 [US2] Implement the section-override mechanism in `charts/library/hl-common/templates/_all.tpl` — call `<chart>.override.<section>` when defined, otherwise the library's own (contracts/library-chart-interface.md)
- [ ] T034 [P] [US2] Write a unit test in `tests/unit/extension_test.yaml` proving a chart-local custom resource carries `hl-common.labels` and release-scoped naming
- [ ] T035 [P] [US2] Write a unit test in `tests/unit/convention_propagation_test.yaml` proving a change to a library default appears in every consuming chart without per-chart edits (FR-005, SC-027)
- [ ] T036 [P] [US2] Write a unit test in `tests/unit/override_test.yaml` proving a declared section override replaces the library's rendering
- [ ] T037 [US2] Document the three sanctioned extension mechanisms in `charts/library/hl-common/README.md`, with a worked example for each

**Checkpoint**: A workload needing a sidecar, a CronJob, or a custom resource fits without a fork.

---

## Phase 5: User Story 3 — Infrastructure dependencies as independent charts (P2)

**Goal**: Database, secret store, and cache are charts in this repository, each its own release,
each deployable and verifiable before any application exists.

**Independent Test**: Deploy each infrastructure chart alone to an empty k3d cluster and confirm it
comes up healthy with durable storage and no manual setup step.

- [ ] T038 [P] [US3] Implement `charts/library/hl-common/templates/_storage.tpl` — explicit `storageClassName` required, retained claims by default (FR-080)
- [ ] T039 [P] [US3] Implement `charts/library/hl-common/templates/_namespace.tpl` — `hl-common.namespace` rendering the Namespace, its ServiceAccount and its VSO `VaultAuth` for one application (FR-040, FR-041)
- [ ] T040 [P] [US3] Implement `charts/library/hl-common/templates/_secrets.tpl` — render a `VaultStaticSecret` per secret reference, with `refreshAfter` and `rolloutRestartTargets` (FR-026, FR-028)
- [ ] T041 [P] [US3] Wire `image.pullSecret` in `charts/library/hl-common/templates/_image.tpl` to a VSO-materialised secret, so a private ghcr.io namespace works without a committed credential (FR-024)
- [ ] T042 [US3] Create the Vault wrapper chart `charts/bootstrap/vault/` pinning chart `vault` 0.34.1, standalone mode, file storage on a retained PVC, with no secret reference of its own (FR-056)
- [ ] T043 [P] [US3] Create the VSO wrapper chart `charts/infrastructure/vault-secrets-operator/` pinning chart `vault-secrets-operator` 1.6.0
- [ ] T044 [P] [US3] Create the CNPG operator wrapper chart `charts/infrastructure/cloudnative-pg/` pinning chart `cloudnative-pg` 0.29.1
- [ ] T045 [US3] Create `charts/infrastructure/postgres/` rendering a CNPG `Cluster` with retained storage, and a values-driven list of per-application databases and roles so adding an application's database is a values change (FR-078) (**depends on T005 confirming Kubernetes 1.31+**)
- [ ] T046 [P] [US3] Create `charts/infrastructure/redis/` built on `hl-common` using a digest-pinned `redis:8-alpine`, no persistence (research R-005)
- [ ] T047 [P] [US3] Add `values.schema.json` to each infrastructure chart
- [ ] T048 [P] [US3] Add `ci/` values fixtures to each infrastructure chart for render testing
- [ ] T049 [US3] Document storage and backup/restore expectations in each stateful chart's README — `charts/bootstrap/vault/README.md` and `charts/infrastructure/postgres/README.md` (FR-065)
- [ ] T050 [US3] Verify each chart under `charts/infrastructure/` and `charts/bootstrap/vault/` installs standalone on k3d with no application present (SC-034)
- [ ] T051 [US3] Verify data survives a chart delete and redeploy for `charts/infrastructure/postgres` (SC-022, US3 acceptance scenario 4)

**Checkpoint**: Every dependency is a chart. No manual setup remains.

---

## Phase 6: User Story 6 — Change applications and dependencies independently (P2)

**Goal**: Application lifecycles and dependency lifecycles never touch, and the dependencies are
left ready for a real service to consume. No application chart contains its dependency.

**Independent Test**: Delete and redeploy an application repeatedly while confirming the
dependency's uptime is unbroken and its data intact.

- [ ] T052 [US6] Implement the dependency-reference surface in `charts/library/hl-common/values.yaml` and `_secrets.tpl` — `host`, `port`, `credentials`, `optional`, supplied as configuration and never assembled from another chart's naming (FR-069, FR-081)
- [ ] T053 [US6] Add `charts/apps/nginx/templates/namespace.yaml` calling `hl-common.namespace`, so the application chart renders its own namespace, service account and VaultAuth (FR-051)
- [ ] T054 [US6] Provision per-application databases, roles, and Vault credentials in `charts/infrastructure/postgres/`, so a future service finds the dependency ready (FR-078)
- [ ] T055 [P] [US6] Provision the cache credential in Vault from `charts/infrastructure/redis/`, and support declaring it `optional: true` (FR-079, FR-082)
- [ ] T056 [P] [US6] Document connection details — address, port, secret path, and the values key a consumer sets — in `charts/infrastructure/postgres/README.md` and `charts/infrastructure/redis/README.md` (FR-080)
- [ ] T057 [P] [US6] Write a unit test in `tests/unit/dependency_reference_test.yaml` rendering a chart that declares both a required and an optional dependency, asserting correct env and readiness output without a real consumer (FR-081)
- [ ] T058 [US6] Verify dependency survival: delete and redeploy `charts/apps/nginx/` 10 times on k3d, confirming `charts/infrastructure/postgres/` uptime and data are untouched (SC-031)
- [ ] T059 [US6] Verify independent upgrade: bump the image in `charts/infrastructure/redis/values.yaml` and confirm no pod from `charts/apps/` is recreated (SC-032)

**Checkpoint**: Application rollbacks no longer put data at risk.

---

## Phase 7: User Story 4 — Rebuild the whole cluster from the repository (P2)

**Goal**: One command on an empty node installs the bootstrap and infrastructure tiers in
dependency order, then Argo CD, which brings up the application tier.

**Independent Test**: Wipe the k3d cluster, run the single command, and confirm every component
converges with no further manual step beyond Vault unsealing.

- [ ] T060 [US4] Create the Argo CD wrapper chart `charts/bootstrap/argocd/` pinning chart `argo-cd` 10.10.5
- [ ] T061 [US4] Create `bootstrap/install-order.yaml` — the pinned install order and values file for each bootstrap and infrastructure chart (FR-055, FR-060)
- [ ] T062 [US4] Create `bootstrap/install.sh` — the single manual command: `helm upgrade --install` each entry of `install-order.yaml` in order, waiting for health, then Argo CD, then `argocd/applicationset.yaml`; accepts an optional `--repo-credential` persisted only into the Argo CD repository Secret (FR-033, FR-058)
- [ ] T063 [P] [US4] Create `bootstrap/argocd-values.yaml` for the Argo CD install
- [ ] T064 [US4] Create `argocd/applicationset.yaml` — a directory generator over `charts/apps/*` deriving the namespace and Application name from the chart directory name, with `prune` and `selfHeal` enabled and `CreateNamespace=false` (FR-030, FR-031, FR-045)
- [ ] T065 [P] [US4] Verify the generator discovers a newly added application chart directory and deploys it into its own namespace, with no manifest written by hand (FR-045)
- [ ] T066 [US4] Verify drift correction on k3d: scale the nginx Deployment by hand and confirm Argo CD returns it to the repository state (FR-031, SC-015)
- [ ] T067 [US4] Write `docs/bootstrap.md` — the rebuild procedure, Vault `operator init` and unseal, where unseal material is stored outside the cluster, and how to upgrade an infrastructure chart with `helm diff upgrade` followed by `helm upgrade` (FR-032, FR-035, FR-059)
- [ ] T068 [P] [US4] Write `docs/tiers.md` — what each tier may depend on, which tier Argo CD manages, and why no bootstrap component may read from Vault
- [ ] T069 [US4] Add a documented command to `docs/tiers.md` for reporting infrastructure state, since Argo CD does not watch those tiers (FR-034, SC-017)
- [ ] T070 [US4] Verify a full cold rebuild on a wiped k3d cluster converges in tier order from `bootstrap/install.sh` alone (SC-018, SC-030)

**Checkpoint**: The repository can rebuild the cluster. Principle I is satisfied in practice.

---

## Phase 8: User Story 7 — Onboard a new service by copying the reference chart (P2)

**Goal**: Onboarding is copy `charts/apps/nginx/`, change a few marked parameters, add one
Application. No variant to choose between.

**Independent Test**: Someone who has not read the foundation follows the guide alone, timed, with
every lookup outside the guide counted.

- [ ] T071 [US7] Annotate every parameter in `charts/apps/nginx/values.yaml` with `# REQUIRED:` or `# OPTIONAL:`, its purpose, and an example value (FR-042)
- [ ] T072 [US7] Give `charts/apps/nginx/values.yaml` placeholder sentinels for name, image, and hostname that fail validation if left unchanged (FR-043)
- [ ] T073 [US7] Implement placeholder rejection in `charts/library/hl-common/templates/_validate.tpl` so an unchanged sentinel fails and names the parameter (FR-043)
- [ ] T074 [US7] Write `docs/onboarding.md` — an ordered sequence from "I have a service" to deployed, requiring no reading of the foundation's internals, and covering secrets, image, and the Application manifest (FR-039, FR-045)
- [ ] T075 [P] [US7] Add the extension section to `docs/onboarding.md` linking to the worked example from T036, and covering the shapes the reference chart does not show — durable storage and dependency references (FR-044)
- [ ] T076 [P] [US7] Write `charts/apps/nginx/README.md` stating it is both a running service and the copy source, and pointing at `charts/infrastructure/postgres/` as the extension example for storage and dependency references (FR-049)
- [ ] T077 [P] [US7] Generate chart READMEs with `helm-docs` (FR-047, SC-028)
- [ ] T078 [US7] Time an onboarding run against `docs/onboarding.md` alone, recording elapsed time, parameters changed, and lookups outside the guide in `docs/validation-results.md` (SC-023, SC-024, SC-025)

**Checkpoint**: A new service is a copy, a few edits, and one manifest.

---

## Phase 9: User Story 5 — Validate a change before it reaches the cluster (P3)

**Goal**: The full gate. Invalid configuration cannot reach the cluster, and every change is
previewable.

**Independent Test**: Introduce a deliberately invalid value and confirm it is rejected at render
time; make a valid change and confirm the pending diff is shown before merge.

> **Recommended to pull forward** — see Implementation Strategy. P3 reflects sequence, not
> importance; this is the only pre-production gate that exists.

- [ ] T079 [P] [US5] Add `values.schema.json` to every remaining chart under `charts/apps/` and `charts/bootstrap/` (FR-008)
- [ ] T080 [US5] Extend `scripts/validate.sh` to the full gate: lint → template over all `ci/` fixtures → `helm unittest` → `kubeconform` at the recorded Kubernetes version → policy checks → `helm-docs` dirty-tree check
- [ ] T081 [P] [US5] Supply CNPG, VSO, and Argo CD CRD schemas to `kubeconform` in `scripts/validate.sh`
- [ ] T082 [P] [US5] Implement policy check 1 in `tests/policy/no_mutable_tags.py` (FR-021, SC-008)
- [ ] T083 [P] [US5] Implement policy check 2 in `tests/policy/no_embedded_dependencies.py`, also rejecting a chart-local copy of a library template (FR-066, SC-033)
- [ ] T084 [P] [US5] Implement policy check 3 in `tests/policy/no_secret_material.py` (FR-020, SC-007)
- [ ] T085 [P] [US5] Implement policy check 4 in `tests/policy/reference_and_tiers.py` — the reference chart renders against the current `hl-common`, and each Application's sync wave matches its tier directory (FR-048, FR-060, SC-026)
- [ ] T086 [US5] Implement `scripts/validate.sh --self-test`, injecting all six deliberate violations and asserting six failures that each name the offending file and value (quickstart step 1)
- [ ] T087 [P] [US5] Implement policy check 5 in `tests/policy/chart_version_bumped.py` — a chart whose templates or defaults changed in the diff must have an advanced `version` (FR-018, Principle VI)
- [ ] T088 [US5] Create `.github/workflows/ci.yaml` running the full gate on every pull request, blocking merge on failure (FR-016)
- [ ] T089 [US5] Document the `helm diff` preview step in `docs/onboarding.md` and require its output in change descriptions (FR-015, Principle III)

**Checkpoint**: No invalid change can reach the cluster.

---

## Phase 10: Polish & Cross-Cutting Concerns

- [ ] T090 [P] Verify secret rotation end to end: rotate in Vault, confirm the consuming workload restarts unaided within `refreshAfter` (quickstart step 7, SC-016)
- [ ] T091 [P] Verify Vault survives a node restart, and that sealing Vault leaves already-running workloads unaffected; document the unseal step in `docs/bootstrap.md` (FR-029, sealed-on-restart edge case)
- [ ] T092 [P] Verify a rollback of `charts/infrastructure/postgres/` leaves its persistent data intact (FR-019, SC-010)
- [ ] T093 [P] Add ingress hostname collision detection to `tests/policy/collisions.py`, alongside the US5 policy checks (hostname-collision edge case)
- [ ] T094 Promote the full stack to the server: run `bootstrap/install.sh` against the real k3s node, then Vault init and unseal (quickstart steps 2–4, requires T005)
- [ ] T095 Verify readiness for real services on the server: nginx reachable over TLS, Postgres and Redis healthy, application database and role present, both credentials resolving in Vault (quickstart step 5, SC-020, SC-036)
- [ ] T096 [P] Record the measured outcome against every success criterion in `docs/validation-results.md`, including the three timings — rebuild duration (SC-005), merge-to-cluster latency (SC-014), and stack-ready duration (SC-020)
- [ ] T097 [P] Write `CLAUDE.md` with runtime agent guidance consistent with the constitution, which Governance already references (constitution.md Governance)
- [ ] T098 [P] Cross-link `README.md`, `docs/onboarding.md`, `docs/bootstrap.md`, and `docs/tiers.md`
- [ ] T099 Run the full `quickstart.md` end to end against the server and correct any step that does not match reality

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies. T005 requires cluster access and gates T044
- **Foundational (Phase 2)**: Depends on Setup. **BLOCKS all user stories**
- **US1 (Phase 3)**: Depends on Foundational. No dependencies on other stories — this is the MVP
- **US2 (Phase 4)**: Depends on US1 (extends what US1 renders)
- **US3 (Phase 5)**: Depends on Foundational. Independent of US1/US2 in principle, though T038 and T039 extend the library
- **US6 (Phase 6)**: Depends on US3 (needs dependencies to decouple from) and US1 (needs an application)
- **US4 (Phase 7)**: Depends on US3 (the install script installs the infrastructure charts) and US1 (the nginx Application needs a chart to point at)
- **US7 (Phase 8)**: Depends on US1 (the reference chart is US1's first consumer) and US2 (the extension section documents US2's mechanisms)
- **US5 (Phase 9)**: Depends on charts existing, but see the pull-forward recommendation below
- **Polish (Phase 10)**: Depends on all desired stories

### Within Each User Story

- Library templates before the charts that consume them
- Charts before their `values.schema.json` and `ci/` fixtures
- Unit tests alongside the templates they cover
- Cluster verification tasks last within the story

### Parallel Opportunities

- Setup: T001, T002, T003, T006 together
- Foundational: T010, T011, T012 together, then T015 and T016 together
- US1: T017, T018, T020, T021, T022, T023 together; later T027, T028, T029 together
- US3: T042, T043, T045 together (distinct upstream wrappers); T046, T047 together
- US4: T061, T063 and T066 together (distinct files)
- US7: T072, T073, T074 together (distinct documentation files)
- US5: T080, T081, T082, T083, T085 together (one file each)

---

## Parallel Example: User Story 1

```bash
# Library templates — distinct files, no interdependencies:
Task: "Implement _resources.tpl in charts/library/hl-common/templates/_resources.tpl"
Task: "Implement _probes.tpl in charts/library/hl-common/templates/_probes.tpl"
Task: "Implement _service.tpl in charts/library/hl-common/templates/_service.tpl"
Task: "Implement _ingress.tpl in charts/library/hl-common/templates/_ingress.tpl"
Task: "Implement _serviceaccount.tpl in charts/library/hl-common/templates/_serviceaccount.tpl"

# Then the unit tests, once the templates exist:
Task: "Write workload assertions in tests/unit/workload_test.yaml"
Task: "Write TLS assertions in tests/unit/ingress_test.yaml"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Phase 1 Setup — tooling and skeleton
2. Phase 2 Foundational — the library primitives
3. Phase 3 US1 — a chart deploys from image, port, and hostname
4. **STOP and VALIDATE**: render it, install it on k3d, re-apply and confirm no diff
5. At this point the foundation is proven and everything else is addition

### Recommended deviation: pull US5 forward

The spec prioritises US5 at P3 because charts must exist before there is anything to validate.
That is true of the *full* gate, but T077 through T086 are cheap once US1 and US2 are done, and
every later phase merges changes that the gate would otherwise not be checking. **Suggested order:
US1 → US2 → US5 → US3 → US6 → US4 → US7.** The homelab has no staging cluster, so the gate is the
only pre-production check that exists; running six phases of chart work without it inverts the
risk the specification was written to manage.

### Incremental Delivery

1. Setup + Foundational → primitives ready
2. US1 → MVP, a deployable application
3. US2 → extensibility proven, the foundation is now safe to build on
4. US5 (pulled forward) → the gate is live before the volume of charts grows
5. US3 → infrastructure stops being manual
6. US6 → lifecycles separated, data safe from application churn
7. US4 → one-command rebuild, the repository becomes the source of truth
8. US7 → onboarding becomes trivial for the next person, including future you

### Blocked work

One input is still needed from outside this repository, and it blocks only the server-side tasks:

- **T005** (and therefore T044, T092, T093) needs a kubeconfig for the server. If the recorded
  Kubernetes version is below 1.31, CloudNativePG is out and T044 needs redesigning before it is
  written — which is why T005 sits in Phase 1 rather than alongside the server work.

Nothing now waits on an application image. Everything through US7 can be built and verified on
k3d, and the delivery is complete when a real service could be added by copying the reference
chart — writing that service is separate work.
