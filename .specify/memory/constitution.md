<!--
Sync Impact Report
Version change: 1.0.0 → 2.0.0
Bump rationale: MAJOR. Principle III is redefined — the human review of a rendered diff moves
  from apply time to a per-tier gate — and the Development Workflow's tagged-commit rule is
  removed. Both change what compliance means, so this is a redefinition rather than expanded
  guidance.
Modified principles:
  I. Declarative Infrastructure as Code — clarified that applying a checked-in script or values
     file is declarative; only unrecorded changes are imperative
  III. Validate Before Apply — human review relocated per tier; validation chain unchanged
Modified sections:
  Development Workflow & Quality Gates — tagged-commit rule replaced with a per-tier deployment
     rule; added infrastructure upgrade procedure and the drift-detection caveat
Added sections: none
Removed sections: none
Deferred items: none
-->

# hl-helm Constitution

Governance for the Helm charts that define and maintain the homelab infrastructure running on a
single-node k3s Linux server.

## Core Principles

### I. Declarative Infrastructure as Code (NON-NEGOTIABLE)

Every cluster resource MUST originate from a chart committed to this repository. A change
applied by running a checked-in script against checked-in values is declarative and permitted —
what the repository records is what the cluster gets, regardless of which mechanism applies it.
Unrecorded changes (`kubectl edit`, `kubectl create`, dashboard edits, `helm install --set` for
anything but a one-off debug session) are NOT a source of truth and MUST be reconciled back into
the repository or reverted within the same working session.

Rationale: A homelab is rebuilt more often than it is maintained. If the repository cannot
reproduce the cluster from an empty k3s node, the infrastructure is not actually maintainable.

### II. Chart-Per-Workload, Shared Library Chart

Each independently deployable workload MUST have exactly one chart with a clear single purpose.
Cross-cutting boilerplate (labels, resource limits, probes, ingress scaffolding, storage claims)
MUST live in a shared library chart or named templates rather than being copy-pasted. Umbrella
charts MAY group workloads for ordering, but MUST NOT embed workload-specific templates.

Rationale: Copy-pasted manifests drift silently; a single shared template makes a convention
change a one-line edit.

### III. Validate Before Apply (NON-NEGOTIABLE)

No chart change reaches the cluster until, in order: `helm lint` passes, `helm template` renders
without error, the rendered output is schema-validated against the target Kubernetes version, and
a rendered diff has been reviewed by a human. Every chart MUST ship a `values.schema.json` so
invalid values fail at render time, not at runtime.

Where that human review happens depends on how the component is applied, and every component MUST
have exactly one of these gates:

- **Continuously reconciled components** (those a deployment agent applies automatically): the
  diff MUST be rendered by CI into the change proposal and reviewed before merge. Merging is
  deploying, so the merge is the gate.
- **Explicitly applied components** (those an operator applies by command): `helm diff upgrade`
  MUST be reviewed immediately before applying. The apply is the gate.

A component that is both auto-applied and has no pre-merge diff rendered is in violation.

Rationale: The homelab has no staging cluster, so rendering and schema validation are the only
pre-production checks that exist, and a human MUST see the diff before it becomes real. Fixing
the review at apply time would forbid continuous reconciliation outright; fixing it at merge time
would waive review for the components where a mistake is least recoverable. Tying the gate to the
apply mechanism keeps a human in the loop for both without forcing one mechanism on everything.

### IV. Environment Parity Through Values

Chart templates MUST be environment-agnostic. All environment differences (hostnames, storage
classes, replica counts, resource sizing, feature toggles) MUST be expressed in values files, never
in conditional template branches keyed on an environment name. Defaults in `values.yaml` MUST be
the safest option, and every value MUST be documented in the chart README.

Rationale: Templates that know about environments cannot be tested in isolation and break the
moment a new environment appears.

### V. Secrets Are Never Plaintext

Plaintext secrets, tokens, passwords, certificates, and kubeconfigs MUST NOT be committed, not even
in example or test values. Secrets MUST be delivered through an encrypted-at-rest mechanism (SOPS,
Sealed Secrets, or an external secrets operator) and referenced by name from charts. Charts MUST
fail rendering when a required secret reference is unset rather than defaulting to a placeholder.

Rationale: Git history is permanent; a secret committed once is a secret rotated forever.

### VI. Idempotent, Reversible Releases

Repeated `helm upgrade --install` of the same chart version against the same values MUST produce no
change. Every chart MUST carry a SemVer `version` that is bumped on any template or default change,
and an `appVersion` tracking the upstream image. Persistent data MUST be decoupled from release
lifecycle (PVCs with `Retain`-class storage or explicit backup) so a rollback never destroys state.

Rationale: Rollback is the only incident response available on a single-node cluster.

### VII. Homelab Simplicity (YAGNI)

Charts MUST target the actual single-node k3s deployment. Multi-region, autoscaling, service-mesh,
and HA abstractions MUST NOT be added speculatively. Prefer k3s built-ins (Traefik, local-path,
ServiceLB) over additional operators unless a concrete, documented need justifies the operational
cost. Any added complexity MUST be justified in the chart README.

Rationale: Every operator added is another thing that breaks at 2am on hardware nobody is paid to
maintain.

## Platform Constraints

- Target platform is a single-node k3s cluster on a Linux server; charts MUST render and apply
  against that topology without external cloud dependencies.
- Manifests MUST be compatible with the k3s Kubernetes minor version recorded in the repository
  README; a version bump is a breaking change requiring a chart major bump where APIs shift.
- Workloads MUST declare resource `requests`, and MUST declare `limits` for memory; the node is
  shared and unbounded workloads can take the cluster down.
- Every long-running workload MUST define liveness and readiness probes.
- Stateful workloads MUST declare an explicit `storageClassName` and an explicit backup or
  restore note in the chart README; implicit reliance on the default storage class is forbidden.
- Ingress MUST route through the cluster ingress controller with TLS; no `NodePort` or `hostPort`
  exposure except where a protocol genuinely cannot traverse the ingress controller, documented
  inline.
- Container images MUST be pinned by explicit tag or digest; `latest` is forbidden.

## Development Workflow & Quality Gates

- Changes are proposed on a branch and merged to `main` only after the Principle III gate has been
  satisfied and its `helm diff` output recorded in the change description.
- CI MUST run, at minimum: `helm lint`, `helm template` for every values file in the chart's
  `ci/` directory, and schema validation of the rendered output. A red gate blocks merge.
- Each chart MUST include a README documenting purpose, every value, storage and backup
  expectations, and any deviation from these principles with its justification.
- How a component reaches the cluster MUST be determined by its tier and recorded in the
  repository. Continuously reconciled components track `main`, so a merge deploys them. Explicitly
  applied components — the secret store and every stateful data service — reach the cluster only
  by an operator running the checked-in bootstrap command, never by a merge alone.
- An upgrade to an explicitly applied component MUST be reviewed with `helm diff upgrade` against
  the running release immediately before it is applied, and MUST be applied from a committed
  state, never from an uncommitted working tree.
- Ad-hoc deploys from a working tree are permitted only for debugging and MUST be rolled back or
  merged the same session.
- Components outside continuous reconciliation have no automatic drift detection. The rebuild
  procedure MUST therefore be exercised on a disposable cluster regularly, not only during an
  incident, since that exercise is the only thing that proves the repository still matches
  reality.
- A chart that has not been rendered in CI for a Kubernetes version bump is considered unverified
  and MUST NOT be upgraded in place.

## Governance

This constitution supersedes other conventions in this repository. Where a chart cannot comply, the
deviation MUST be documented in that chart's README with its rationale and an expiry condition;
undocumented deviations are defects.

Amendments are made by editing this file in a dedicated commit that states the change, its
rationale, and its impact on existing charts. Versioning follows SemVer: MAJOR for removing or
redefining a principle in a backward-incompatible way, MINOR for adding a principle or materially
expanding guidance, PATCH for clarifications and wording. An amendment that invalidates existing
charts MUST include a migration note listing the charts to update.

Compliance is reviewed at every merge against the quality gates above, and re-reviewed in full
whenever the k3s version is upgraded. Runtime agent guidance lives in `CLAUDE.md` and MUST stay
consistent with this document; where they conflict, this document wins.

**Version**: 2.0.0 | **Ratified**: 2026-10-16 | **Last Amended**: 2026-10-16
