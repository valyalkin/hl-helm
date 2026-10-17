# Feature Specification: Extensible Helm Charts for Homelab Applications and Infrastructure

**Feature Branch**: `001-extensible-helm-charts`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "I would like to create helm charts for my applications. Helm charts should be easily extendable through templates. Most of the infrastructure must also be supported through helm charts."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy an application from a reusable chart foundation (Priority: P1)

The homelab operator wants to run one of their own applications on the cluster. Instead of
hand-writing a full set of manifests, they describe the application — its image, the port it
listens on, the hostname it should answer at, and how much memory it may use — and the shared
chart foundation produces a complete, correct deployment: workload, service, ingress with TLS,
probes, and resource limits.

**Why this priority**: This is the core value. Without it there is nothing to extend and no reason
to adopt the repository. A single application deployed this way is already a working MVP.

**Independent Test**: Fully testable by describing one application's values, rendering the chart,
and confirming the rendered output is a complete and valid set of cluster resources that deploys
successfully — no other story needs to exist.

**Acceptance Scenarios**:

1. **Given** a new application described only by image, port, and hostname, **When** the operator
   renders the chart, **Then** the output contains a workload, service, and TLS-enabled ingress
   with probes and resource limits populated from safe defaults.
2. **Given** an application values file that omits a required field, **When** the operator renders
   the chart, **Then** rendering fails with a message naming the missing field, and no partial
   output is produced.
3. **Given** an application values file setting a memory limit and replica count, **When** the
   operator renders the chart, **Then** those values appear in the output in place of the defaults.
4. **Given** an application already deployed, **When** the operator re-applies the same chart
   version with unchanged values, **Then** the cluster reports no changes.

---

### User Story 2 - Extend a chart for an application that does not fit the defaults (Priority: P1)

An application needs something the shared foundation does not cover out of the box — an extra
sidecar, a scheduled job, a non-HTTP port, a custom resource from an operator. The operator adds
only the piece that is unique to that application and still inherits every shared convention
(naming, labels, probes, limits, ingress) without copying boilerplate.

**Why this priority**: The user explicitly asked for extensibility. A chart foundation that only
handles the common case forces a fork on first contact with a real workload, which destroys its
value. Equal priority to Story 1 because the two together are the actual ask.

**Independent Test**: Testable by taking an application that needs a resource the foundation does
not provide, adding only that resource, and confirming the rendered output contains both the
custom resource and all shared conventions, with no duplicated boilerplate.

**Acceptance Scenarios**:

1. **Given** an application requiring an additional resource not covered by the foundation,
   **When** the operator adds that resource to the application's own chart, **Then** the rendered
   output includes it alongside the foundation-generated resources, carrying the same naming and
   labels.
2. **Given** a convention change made once in the shared foundation, **When** every chart is
   re-rendered, **Then** the change appears in all of them without per-chart edits.
3. **Given** an application that must override a shared default the foundation normally enforces,
   **When** the operator sets the override in that application's values, **Then** the override
   takes effect and the reason is recorded in that chart's documentation.
4. **Given** a new application of a shape already seen before, **When** the operator creates its
   chart, **Then** no shared boilerplate is copied — only the application's own distinct values
   and resources are written.

---

### User Story 3 - Run infrastructure dependencies as independent charts (Priority: P2)

Every dependency the applications rely on — database, secret store, cache, and whatever is added
later — is described in this repository, pinned to a version, given durable storage, and deployed
from the repository rather than set up by hand. Each is its own release with its own lifecycle,
deployable and verifiable before any application that consumes it exists.

**Why this priority**: The operator does not want to rely on manual setup for anything. This is
the story that removes it. It depends on the foundation from Stories 1 and 2 existing first, but
it is what proves the pattern generalises beyond stateless applications and makes the cluster
genuinely reproducible.

**Independent Test**: Testable by deploying each infrastructure chart on its own to an empty
cluster and confirming it comes up healthy with durable storage, with no application deployed and
no manual step performed.

**Acceptance Scenarios**:

1. **Given** an infrastructure dependency described in the repository, **When** the operator
   renders it, **Then** the output pins an explicit upstream version and applies the homelab's own
   configuration on top.
2. **Given** an empty cluster, **When** the operator deploys an infrastructure chart alone,
   **Then** it comes up healthy with no application present and no manual setup step.
3. **Given** a stateful infrastructure chart, **When** it is described in the repository, **Then**
   its storage and its backup or restore expectations are stated explicitly rather than left to
   cluster defaults.
4. **Given** a deployed database holding data, **When** its chart is deleted and re-deployed,
   **Then** the data survives.
5. **Given** a new infrastructure dependency to add, **When** the operator onboards it, **Then**
   they follow the same path as any other component — copying the reference chart — rather than
   writing a bespoke chart.

---

### User Story 4 - Rebuild the whole cluster from the repository (Priority: P2)

Starting from a freshly installed, empty k3s node, the operator performs one bootstrap step and
everything follows from the repository — the deployment agent, the secret store, the database and
cache, then the reference service — without consulting notes kept outside the repository.

**Why this priority**: This is the end state the constitution demands and the real test of whether
the repository is the source of truth. It is scored after the per-chart stories because it is
verified by composing them. With the cluster being rebuilt from scratch, this story is how the
rebuild actually happens rather than a hypothetical exercise.

**Independent Test**: Testable by wiping the node, performing the single bootstrap command, and
confirming every component — deployment agent, secret store, database, cache, reference service
— comes up with no manual step beyond that one command and the secret store's unsealing.

**Acceptance Scenarios**:

1. **Given** an empty cluster, **When** the operator performs the single documented bootstrap
   command, **Then** the secret store and the infrastructure tier are installed in dependency
   order, the deployment agent is installed last, and the agent brings up the application tier,
   with no further manual step.
2. **Given** a rebuild, **When** the secret store is first installed, **Then** it requires no
   secret from itself to start, and its initialisation produces material the operator stores
   outside the cluster.
3. **Given** a rebuild in progress, **When** a secret is required, **Then** it is read from the
   secret store and no secret value is read from the repository itself.
4. **Given** a completed rebuild, **When** the operator compares the result to the intended state,
   **Then** the set of running services and their configuration match.
5. **Given** a rebuild where the secret store is sealed or unreachable, **When** deployment is
   attempted, **Then** the affected components fail visibly with a message naming the missing
   secrets, rather than starting with empty credentials.

---

### User Story 5 - Validate a change before it reaches the cluster (Priority: P3)

Before a change is merged, the operator sees exactly what will change. Invalid values are caught
while rendering rather than by a crashing pod, and the difference against what is currently
running is reviewable. Once merged, the deployment agent applies it and keeps the cluster matching
the repository.

**Why this priority**: The constitution makes this non-negotiable, and the homelab has no staging
cluster. It is P3 only in sequence — the charts must exist before there is something to validate —
not in importance.

**Independent Test**: Testable by introducing a deliberately invalid value and confirming it is
rejected at render time, and by making a valid change and confirming the pending difference is
shown before anything is applied.

**Acceptance Scenarios**:

1. **Given** a chart with an invalid value (wrong type, out-of-range, unknown field), **When**
   validation runs, **Then** it fails with a message naming the offending value, before anything
   reaches the cluster.
2. **Given** a valid change to a deployed chart, **When** the operator previews it, **Then** the
   exact set of resources that would change is shown before the change is merged.
3. **Given** a change proposed for merge, **When** automated checks run, **Then** every chart is
   linted, rendered against each of its test value sets, and schema-validated, and a failure
   blocks the merge.
4. **Given** a change applied manually to an application-tier component rather than through the
   repository, **When** the deployment agent next reconciles, **Then** the drift is reported and
   the component is returned to the repository state.

---

### User Story 6 - Change applications and dependencies independently (Priority: P2)

The operator redeploys an application three times in an afternoon and the database never
notices. Later they upgrade the database's version, and the applications keep running throughout.
Neither side's lifecycle is tied to the other's, and no deployment of one risks the data of the
other.

**Why this priority**: The operator asked explicitly for infrastructure to be decoupled from
application deployments. Coupling them is the single easiest mistake to make here — embedding a
database as a subchart of the application that uses it is the conventional shortcut, and it means
every application rollback becomes a database rollback. This story exists to make that
impossible.

**Independent Test**: Testable by deploying an application and its dependency, then deleting and
redeploying the application repeatedly while confirming the dependency's uptime is unbroken and
its data intact.

**Acceptance Scenarios**:

1. **Given** a deployed application and the database it would consume, **When** the application
   is deleted and redeployed, **Then** the database stays running throughout and its data is
   intact.
2. **Given** a deployed application, **When** its dependency is upgraded to a new version, **Then**
   the application is not redeployed, and recovers on its own if the dependency restarts.
3. **Given** an application chart, **When** the operator inspects it, **Then** it does not contain
   or install its dependencies — it only references them.
4. **Given** two applications consuming the same dependency, **When** either is removed, **Then**
   the dependency and the other application are unaffected.
5. **Given** an application that starts before its dependency is reachable, **When** the dependency
   becomes available, **Then** the application becomes ready on its own without intervention.
6. **Given** an application rollback to a previous version, **When** it completes, **Then** no
   dependency has been rolled back, restarted, or had its data altered.

---

### User Story 7 - Onboard a new service by copying the reference chart (Priority: P2)

The operator wants to add a service that did not exist when the repository was written. They open
the onboarding guide, copy the reference chart, change a handful of named parameters, and have a
deployable chart — without reading the shared foundation's internals, and without deciding
anything the foundation could have decided for them.

**Why this priority**: This is what turns the foundation from something only its author can use
into something that is still usable in six months. It depends on Stories 1 and 2 existing first,
which is why it is P2 rather than P1 — but it is the story that determines whether the repository
is actually maintained or quietly abandoned.

**Independent Test**: Testable by having someone who has not read the foundation follow the guide
alone and successfully onboard a service, measuring the time taken and the number of times they
had to look beyond the guide.

**Acceptance Scenarios**:

1. **Given** the onboarding guide and the reference chart, **When** the operator copies it and
   changes only the parameters the guide names, **Then** the result renders into a complete,
   valid, deployable chart with no further edits.
2. **Given** a copied chart, **When** the operator inspects it, **Then** every line in it is a
   parameter specific to their service — no shared boilerplate was copied, and a later change to
   a shared convention still reaches the new chart.
3. **Given** a service that matches the reference chart's shape, **When** the operator follows the
   guide end to end, **Then** the service is deployed and reachable without them having read the
   shared foundation's templates.
4. **Given** a copied chart with a parameter left at its placeholder value, **When** validation runs,
   **Then** it fails naming that parameter, rather than deploying something half-configured.
5. **Given** a service that needs something the reference chart does not cover, **When** the
   operator consults the guide, **Then** the guide explains how to extend the chart and points to
   a worked example.
6. **Given** a new convention added to the foundation, **When** the guide is next used, **Then**
   the guide and the reference chart reflect it, because keeping them current is part of changing
   the foundation.

---

### Edge Cases

- An application needs a protocol that cannot pass through the HTTP ingress; the chart must allow a
  documented exception rather than forcing a workaround.
- Two charts claim the same hostname, port, or storage volume; the conflict must surface at
  validation time, not as a silent takeover in the cluster.
- A rollback is issued for a release whose previous version used a different storage layout;
  persistent data must survive the rollback.
- An upstream third-party component publishes a new version with changed configuration keys; the
  repository must pin the old version until the change is made deliberately.
- The cluster's Kubernetes version is upgraded and an API version a chart uses is removed; affected
  charts must be identified before the upgrade, not after.
- A required secret is absent at deploy time; rendering must fail clearly rather than deploying a
  workload with an empty credential.
- The single node is under memory pressure; a new workload's declared limits must prevent it from
  evicting existing services.
- The secret store is unreachable while a deployment is attempted; already-running workloads must
  be unaffected and the failure must be clearly attributed to the store rather than to the chart.
- A secret is rotated in the store while workloads are running; consumers that cannot reload it
  must be restarted, and consumers that can must pick it up without a restart.
- The registry is unreachable or a pull credential has expired; the failure must be distinguishable
  from an application crash.
- The deployment agent is itself deleted or broken; recovering it must not require recovering the
  rest of the cluster by hand.
- The deployment agent manages its own configuration; a bad change to that configuration must not
  leave the agent unable to deploy the fix.
- An urgent manual fix is applied directly to an application during an incident; the agent must
  not silently revert it before the operator has committed it, yet must not leave the drift
  indefinitely unreported.
- An infrastructure component is changed by hand and never committed; nothing detects it, so the
  rebuild procedure must be exercised periodically rather than trusted on faith.
- A configuration file is changed but its workload reloads without a restart; the chart's opt-out
  must be deliberate and documented, not a default that hides a stale config.
- A service starts before the database is accepting connections; the foundation must let it
  report itself unready rather than crash-loop or serve errors as if healthy.
- A database credential is rotated while a consumer holds open connections; the consumer must be
  able to recover without manual intervention.
- The database's storage fills; the failure must be visible before it silently corrupts writes.
- An image is rebuilt and redeployed; it must pick up dependency addresses from its deployment
  configuration, not from whatever was baked in at build time.
- An operator copies the reference chart and forgets to change a parameter, leaving a name or hostname that
  collides with an existing service; validation must catch the collision rather than the new chart
  taking over the existing one's traffic.
- A new service needs a shape the reference chart does not show, such as durable storage; the
  guide must lead somewhere useful rather than dead-ending.
- The foundation gains a required parameter; the reference chart must be updated in the same
  change, or charts copied from it will be invalid on arrival.
- The guide drifts out of step with the foundation; the mismatch must be detectable rather than
  discovered by an operator following stale instructions.
- The secret store restarts and comes back sealed; applications already running must be
  unaffected, and the operator must be told clearly that unsealing is required.
- The deployment agent is asked to manage the secret store that the agent itself draws no secrets
  from; the dependency direction must stay one-way, with no component in the bootstrap tier
  reaching back into the infrastructure tier.
- An application chart is written with its database embedded as a subchart; this must be caught
  before merge, since it silently couples the two lifecycles.
- A dependency is deleted while applications still consume it; the applications must degrade
  visibly rather than fail silently, and the deletion must be reported as drift.
- The cache is unavailable; a consumer that declared it optional must continue serving at reduced
  performance rather than failing, since the cache is an accelerator and not a system of record.
- Two applications consume the same database and one is rolled back to a version expecting an
  older schema; the spec does not solve this, but the chart must not make it worse by coupling the
  rollback to the database's lifecycle.

## Requirements *(mandatory)*

### Functional Requirements

**Shared foundation and extensibility**

- **FR-001**: The repository MUST provide a shared chart foundation that generates a complete,
  deployable set of resources for a typical application from a minimal description.
- **FR-002**: The shared foundation MUST apply naming, labelling, probe, resource-limit, and
  ingress conventions consistently to every chart that uses it.
- **FR-003**: A chart MUST be able to add resources the foundation does not provide without
  copying any foundation-provided boilerplate.
- **FR-004**: A chart MUST be able to override any foundation-supplied default through its own
  values, without modifying the foundation.
- **FR-005**: A change to a shared convention MUST take effect in every consuming chart without
  per-chart edits.
- **FR-006**: Each chart MUST have exactly one clear purpose; grouping multiple workloads MUST be
  expressed by composition rather than by embedding one workload's resources in another's chart.

**Configuration and documentation**

- **FR-007**: Every configurable value MUST be documented with its purpose, its default, and
  whether it is required.
- **FR-008**: Every chart MUST declare a machine-checkable schema for its values so invalid
  configuration is rejected at render time.
- **FR-009**: Defaults MUST be the safest option available; an unsafe configuration MUST require an
  explicit opt-in.
- **FR-010**: Differences between deployment contexts MUST be expressed purely as configuration
  values, never as context-aware branching inside templates.

**Infrastructure coverage**

- **FR-011**: Platform services the applications depend on MUST be described in the repository
  using the same mechanisms as the applications.
- **FR-012**: Third-party components MUST be pinned to an explicit version and configured through
  the repository rather than by hand after installation.
- **FR-013**: Ordering dependencies between components MUST be expressed so that a full deployment
  applies them in a satisfiable order.
- **FR-014**: Stateful components MUST state their storage requirements and their backup or restore
  expectations explicitly.

**Validation and safety**

- **FR-015**: The repository MUST support previewing the exact set of changes a deployment would
  make before any change is applied.
- **FR-016**: Automated checks MUST lint, render, and schema-validate every chart against each of
  its test value sets, and MUST block a change that fails.
- **FR-017**: Re-deploying an unchanged chart version with unchanged values MUST produce no change
  in the cluster.
- **FR-018**: Every chart MUST carry a version that is advanced whenever its templates or defaults
  change.
- **FR-019**: A release MUST be able to be rolled back to its previous version without destroying
  persistent data.
- **FR-020**: Secrets MUST NOT be stored in readable form anywhere in the repository, including in
  examples and test values; a chart MUST fail rather than substitute a placeholder for a missing
  required secret.
- **FR-021**: Container images MUST be referenced by an explicit version; a mutable rolling
  reference MUST be rejected by validation.
- **FR-022**: An empty cluster MUST be able to be brought to the intended running state using only
  the repository and its secret mechanism.

**Images and registry**

- **FR-023**: Charts MUST reference container images from the operator's own registry namespace by
  default, requiring only the image name and version in a chart's configuration rather than a full
  repeated registry path.
- **FR-024**: Charts MUST support pulling from a private registry namespace, obtaining the pull
  credential through the secret mechanism rather than from a value committed to the repository.
- **FR-025**: A chart MUST be able to reference an image outside the default registry namespace
  when an upstream third-party component requires it.

**Secret delivery**

- **FR-026**: Secrets MUST be delivered to the cluster from the external secret store; a chart MUST
  reference a secret by its path and key in that store and MUST NOT contain the secret value.
- **FR-027**: A chart that references a secret absent from the store MUST fail deployment
  visibly, naming the missing path, rather than starting a workload with an empty credential.
  Validation MUST catch every malformed reference at render time; existence in the store can only
  be checked at deployment time.
- **FR-028**: A rotated secret MUST reach the workloads that consume it without a chart change, and
  a workload that cannot observe a rotation while running MUST be restarted automatically when its
  secret changes.
- **FR-029**: The secret store's own availability MUST NOT be required for an already-running
  workload to keep running; a store outage MUST affect only new deployments and rotations.

**Continuous deployment**

- **FR-030**: Application-tier deployments MUST be performed by an in-cluster agent that
  continuously reconciles those components against the repository. Infrastructure-tier and
  bootstrap-tier components MUST NOT be managed by the agent; they are deployed by the bootstrap
  command from charts in this repository.
- **FR-031**: Manual changes made directly to an application-tier component MUST be reported as
  drift and MUST be corrected back to the repository state without operator action.
- **FR-032**: An infrastructure-tier change MUST reach the cluster only through an explicit
  operator action, so that a merge alone cannot restart or reconfigure a data service.
- **FR-033**: Bringing up an empty cluster MUST be a single documented command that installs the
  bootstrap and infrastructure tiers in dependency order and then the deployment agent, after
  which the agent manages the application tier and its own configuration.
- **FR-034**: The deployment agent MUST report, for every application-tier component, whether the
  cluster matches the repository and whether the component is healthy. Infrastructure state MUST
  be determinable by a documented command.
- **FR-035**: A failed application deployment MUST be able to be returned to its previous state
  through the agent. A failed infrastructure deployment MUST be able to be rolled back by a
  documented command without destroying persistent data.

**Application configuration**

- **FR-036**: All application configuration MUST be maintained in the charts; a workload MUST NOT
  depend on configuration created or edited outside the repository.
- **FR-037**: A configuration change MUST reach the running workload. The foundation MUST restart
  the workload on a configuration change by default, and a chart MUST be able to opt out when its
  workload reloads configuration without a restart, with the reason recorded in its README.
- **FR-038**: Configuration MUST be expressible both as structured values the chart renders into
  the required format and as whole files carried verbatim, so that an application with its own
  configuration file format is supported without escaping it into values.

**Onboarding and documentation**

- **FR-039**: The repository MUST provide an onboarding guide that takes an operator from "I have
  a service to deploy" to a deployed service, as a single ordered sequence of steps with no
  prerequisite reading of the shared foundation's internals.
- **FR-040**: The repository MUST provide a single reference chart that an operator copies and
  modifies. Onboarding MUST NOT require writing a chart from scratch, and MUST NOT require
  choosing between variants.
- **FR-041**: The reference chart MUST contain only parameters specific to the service it
  deploys. It MUST NOT contain copied boilerplate, so that later changes to shared conventions
  continue to reach charts created from it.
- **FR-042**: Every parameter an operator must change MUST be marked as such and explained in
  place, with its purpose and an example value.
- **FR-043**: A parameter left at its placeholder value MUST fail validation, naming the
  parameter, rather than deploying a partially configured service.
- **FR-044**: The onboarding guide MUST state explicitly how to extend a chart beyond what the
  the reference chart covers, and MUST link to a worked example of such an extension.
- **FR-045**: The onboarding guide MUST document how a new service obtains its secrets, its image,
  and its place in the deployment agent's configuration, so that onboarding does not stop at a
  rendered chart.
- **FR-046**: Documentation MUST be kept current as part of changing the foundation: a change that
  adds, removes, or renames a parameter an operator sets MUST update the guide and every affected
  the reference chart in the same change.
- **FR-047**: Automated checks MUST verify that the reference chart still renders and validates
  against the current foundation, so that stale documentation is caught before an operator follows
  it.
- **FR-048**: The reference chart MUST be a real, continuously deployed workload rather than an
  inert template, and the infrastructure charts MUST serve as the worked examples of extension, so that
  the documentation's examples are real deployed charts rather than illustrations that can drift.

**Deployment tiers and bootstrap**

- **FR-049**: Components MUST be organised into tiers by what they depend on: a bootstrap tier that
  depends on nothing inside the cluster, an infrastructure tier that may depend on the bootstrap
  tier, and an application tier that may depend on both.
- **FR-050**: No component in the bootstrap tier may require a secret from the secret store, so
  that bringing up an empty cluster never requires the secret store to already be running.
- **FR-051**: The secret store and the deployment agent MUST both be described as charts in this
  repository and installed by the bootstrap command. Neither may be configured ad hoc or left as
  an undocumented manual step.
- **FR-052**: Bringing up an empty cluster MUST require exactly one manual command, after which
  every remaining component — including the deployment agent's own ongoing configuration and the
  secret store — is installed from the repository.
- **FR-053**: The secret store's initialisation and unsealing procedure MUST be documented, and the
  material produced by initialisation MUST be stored outside the cluster. The repository MUST NOT
  contain that material.
- **FR-054**: An operator MUST be able to determine which tier a component belongs to from the
  repository alone, without inferring it from deployment order.

**Infrastructure dependencies**

- **FR-055**: Every infrastructure dependency the applications rely on — relational database,
  secret store, cache, and any added later — MUST be described as a chart in this repository. No
  infrastructure dependency may require manual setup.
- **FR-056**: Infrastructure dependencies MUST be deployable to an empty cluster from the
  repository alone, with no step performed outside it beyond the single bootstrap command.
- **FR-057**: Adding a new infrastructure dependency MUST follow the same onboarding path as any
  other component, copying the reference chart rather than writing a bespoke one.
- **FR-058**: Each infrastructure dependency MUST pin an explicit upstream version and apply the
  homelab's configuration on top, rather than tracking a moving upstream default.
- **FR-059**: Each stateful infrastructure dependency MUST declare its storage explicitly and state
  its backup and restore expectations in its own documentation.

**Decoupling applications from their dependencies**

- **FR-060**: An infrastructure dependency MUST be its own chart with its own release lifecycle. An
  application chart MUST NOT embed the dependency it consumes.
- **FR-061**: Deploying, upgrading, rolling back, or deleting an application MUST leave the
  infrastructure dependencies it consumes untouched and running.
- **FR-062**: Upgrading an infrastructure dependency MUST NOT require redeploying the applications
  that consume it, beyond a restart where the application cannot reconnect on its own.
- **FR-063**: An application MUST reach its dependencies through a stable address supplied as
  configuration, never through an address assembled from another chart's internal naming.
- **FR-064**: An infrastructure dependency MUST be deployable and verifiable on its own, before any
  application that consumes it exists.
- **FR-065**: Multiple applications MUST be able to consume the same infrastructure dependency
  without any of them owning its lifecycle.
- **FR-066**: Persistent data MUST survive deletion and redeployment of every application that
  consumes it.
- **FR-067**: An application MUST start, report itself unready, and recover on its own when a
  dependency is unavailable at startup, rather than requiring a deployment ordering guarantee to
  function.

**First delivery scope**

- **FR-068**: The first delivery MUST cover the shared chart foundation, the bootstrap tier (the
  deployment agent and the secret store), the infrastructure tier (a relational database and a
  cache), and one reference application chart. It MUST NOT include any business application; the
  deliverable is a repository ready for real services, not the services themselves.
- **FR-069**: The delivered charts MUST exercise distinct workload shapes — a stateless service
  with ingress, and stateful data services — so that the foundation is proven against more than
  one shape before real services are written.
- **FR-070**: The reference chart MUST require only minimal configuration to deploy: the image
  version and the hostname. Everything else MUST come from foundation defaults.
- **FR-071**: The database MUST use durable storage whose lifecycle is independent of the release,
  so that deleting and re-deploying the database chart does not destroy its data.
- **FR-072**: The database MUST be delivered ready for consumption: reachable at a stable
  in-cluster address, with an application database and role already created, and credentials
  already present in the secret store.
- **FR-073**: The cache MUST be delivered ready for consumption: reachable at a stable in-cluster
  address, with any credentials already present in the secret store.
- **FR-074**: Each dependency's connection details — address, port, secret path, and the values
  key a consuming chart sets — MUST be documented in that dependency's README, so a future
  service can consume it without reading its templates.
- **FR-075**: The foundation MUST provide the dependency-reference and secret-reference surfaces a
  future service will need, and these MUST be demonstrated by rendering, independently of whether
  a consuming service exists yet.
- **FR-076**: A future service MUST be able to declare a dependency as optional, so that it stays
  functional with reduced capability when that dependency is unavailable; the cache is the
  intended first use of this.
- **FR-077**: The delivered stack MUST be deployable to an empty cluster using only the repository
  and the single bootstrap command, producing a reachable reference service and healthy database
  and cache.
- **FR-078**: Onboarding a real service onto the delivered dependencies MUST require no change to
  any infrastructure chart — only a new application chart and its Application manifest.

### Key Entities

- **Shared chart foundation**: The reusable conventions every chart inherits — naming, labels,
  probes, resource limits, ingress, storage claims. Changed in one place, applied everywhere.
- **Application chart**: One of the operator's own applications, described by its image, exposed
  endpoints, storage needs, resource sizing, and any resources unique to it.
- **Infrastructure chart**: A dependency the applications rely on, wrapping a pinned third-party
  component with the homelab's own configuration, with its own release lifecycle independent of
  anything that consumes it. In this delivery: the secret store, the database, and the cache.
- **Tier**: A component's dependency class — bootstrap (depends on nothing in the cluster),
  infrastructure (may depend on bootstrap), application (may depend on both). Determines what a
  component may rely on and the order a rebuild follows.
- **Dependency reference**: The stable address and credential reference by which an application
  reaches an infrastructure dependency, supplied as configuration so neither side's chart needs to
  know the other's internals.
- **Delivered stack**: What a rebuild produces — deployment agent, secret store, database,
  cache, and the reference service — collectively demonstrating that the foundation holds across
  tiers and leaving the dependencies ready for real services.
- **Values set**: A named collection of configuration for one chart in one context, carrying
  everything that differs from the chart's defaults.
- **Secret reference**: A pointer from a chart to a path and key in the external secret store;
  never the credential itself.
- **Application configuration**: The settings a workload needs to run, held in the chart either as
  structured values the chart renders or as whole files carried verbatim, and never created or
  edited outside the repository.
- **Release**: One deployed instance of a chart at a specific version with a specific values set,
  able to be previewed, re-applied without effect, and rolled back.
- **Reconciliation state**: For each component, whether the cluster currently matches the
  repository and whether the component is healthy — the signal the operator reads to know the
  cluster's true state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can add a new typical application to the cluster — from nothing to
  running and reachable — in under 30 minutes, writing only that application's own distinct
  configuration.
- **SC-002**: Adding a typical application requires writing no more than 30 lines of configuration,
  with zero lines copied from an existing chart.
- **SC-003**: A change to a shared convention reaches every chart through a single edit, verified
  by every chart reflecting the change on the next render.
- **SC-004**: 100% of intended cluster services can be re-created from the repository alone,
  starting from an empty node, with zero manual steps performed outside it.
- **SC-005**: A full rebuild of the cluster from an empty node completes in under 2 hours.
- **SC-006**: 100% of invalid configurations are rejected before reaching the cluster, measured by
  a set of deliberately invalid inputs, each caught at validation time.
- **SC-007**: Zero secrets are readable in the repository or its history, verified by an automated
  scan on every change.
- **SC-008**: Zero workloads reference a mutable rolling image version, verified by validation on
  every change.
- **SC-009**: Every deployment is previewable, with the operator seeing the complete set of
  intended changes before any of them is applied, in 100% of deployments.
- **SC-010**: Any release can be returned to its previous version in under 5 minutes with no loss
  of persistent data.
- **SC-011**: Re-deploying an unchanged configuration produces zero changes in the cluster, in 100%
  of cases.
- **SC-012**: Every configurable value is documented, measured as 100% coverage of values against
  their documentation.
- **SC-013**: Zero application configuration exists outside the repository, verified by confirming
  every running workload's configuration can be traced to a chart.
- **SC-014**: A merged application-tier change reaches the cluster without operator intervention,
  within 10 minutes of merge, in 100% of cases.
- **SC-015**: Manual changes made directly to an application-tier component are reported within
  10 minutes and corrected, in 100% of cases.
- **SC-016**: A rotated secret reaches every workload that consumes it within 1 hour, with no chart
  change required.
- **SC-017**: The operator can determine application-tier sync and health from the deployment
  agent, and infrastructure-tier state from one documented command.
- **SC-018**: Bootstrapping an empty cluster requires exactly one manual step before the deployment
  agent takes over everything else.
- **SC-019**: Each delivered chart needs no more than 20 lines of its own configuration to
  deploy, with everything else inherited from foundation defaults.
- **SC-020**: The complete stack — reference service reachable, database and cache healthy — is
  running within 15 minutes of starting a deployment to an empty cluster.
- **SC-021**: The delivered charts share 100% of their boilerplate through the foundation, with
  zero lines duplicated between them.
- **SC-022**: Deleting and re-deploying the database chart preserves 100% of its data.
- **SC-036**: A real service can be onboarded onto the delivered database and cache with zero
  changes to any infrastructure chart.
- **SC-023**: An operator who has not read the shared foundation can onboard a new service of a
  known shape in under 15 minutes, following the guide alone.
- **SC-024**: Onboarding a new service requires changing no more than 10 named parameters in a
  copied reference chart.
- **SC-025**: An operator completes onboarding without needing to consult anything beyond the
  guide, in 100% of attempts for services matching a supported shape.
- **SC-026**: The reference chart renders, validates, and deploys successfully on every change,
  verified automatically.
- **SC-027**: Zero lines of shared boilerplate appear in a copied chart, verified by confirming a
  foundation convention change reaches a chart created from the reference without editing it.
- **SC-028**: Every parameter an operator is expected to set is documented in place, measured as
  100% coverage.
- **SC-029**: Zero infrastructure dependencies require a manual setup step; 100% are deployable
  from the repository alone.
- **SC-030**: Bringing an empty node to a fully running cluster requires exactly one manual
  command.
- **SC-031**: An application can be deleted and redeployed 10 times consecutively with zero
  interruption to its dependencies and zero loss of their data.
- **SC-032**: An infrastructure dependency can be upgraded with zero application charts
  redeployed.
- **SC-033**: Zero application charts contain or install an infrastructure dependency, verified
  automatically on every change.
- **SC-034**: Each infrastructure dependency can be deployed and verified healthy on its own, with
  no application present, in 100% of cases.
- **SC-035**: An application started before its dependencies are available becomes ready on its
  own within 2 minutes of them becoming available, with no intervention.

## Assumptions

- The target is a single-node homelab cluster maintained by one operator; multi-tenancy, team
  access control, and multi-cluster support are out of scope.
- The operator is technically proficient and comfortable operating the cluster directly; the
  deliverable is a repository and its documentation, not a user interface.
- "Most of the infrastructure" means the platform services the operator's applications depend on —
  ingress, certificates, storage, observability, backups — and explicitly excludes the operating
  system, the cluster installation itself, networking hardware, and anything outside the cluster.
- Third-party components are consumed from their upstream published charts, wrapped and pinned,
  rather than re-implemented in this repository.
- Applications are containerised and their images are already published to a registry the cluster
  can reach; building images is out of scope.
- Deployments are expected to tolerate brief downtime during upgrades; zero-downtime rollout is not
  a requirement on a single node.
- High availability, autoscaling, and multi-region concerns are out of scope per the project
  constitution's simplicity principle.
- Backups are expected to be configured and verifiable, but the off-site storage destination itself
  is assumed to already exist.
- The cluster's Kubernetes version is treated as a fixed, recorded baseline; upgrading it is a
  separate, deliberate exercise.
- Container images for the operator's own applications are published to and pulled from GitHub
  Container Registry (ghcr.io); building and publishing those images happens elsewhere and is out
  of scope. Upstream third-party components may be pulled from their own registries.
- Secrets are held in Vault and reach the cluster through an in-cluster integration; charts carry
  only the path and key. Vault itself is a deliverable of this feature, deployed from a chart in
  the bootstrap tier. Its unseal material is produced at initialisation and stored outside the
  cluster by the operator; the repository never contains it.
- Argo CD manages the application tier only, reconciling it continuously against `main`, so
  merging an application change deploys it. Vault, the Vault Secrets Operator, CloudNativePG,
  PostgreSQL and Redis are deployed by the bootstrap command from pinned charts in this
  repository and are deliberately outside Argo CD: a merge must never restart a data service on
  its own. The trade is accepted knowingly — infrastructure drift is not detected automatically,
  and infrastructure upgrades are an explicit operator action.
- The cluster is built from scratch. The existing Postgres and Vault instances currently running on
  the node are to be cleared, so no adoption of live resources or migration of existing data is
  required, and no chart needs to accommodate state created outside this repository.
- Infrastructure dependencies are deployed as independent releases, in their own namespaces,
  separate from the applications that consume them. An application chart never installs its own
  dependency.
- The cache (Redis) is treated as an accelerator rather than a system of record: losing its
  contents degrades performance but does not lose data.
- All application configuration lives in the charts. Applications that insist on writing their own
  configuration at runtime are accepted as an exception only where unavoidable, and the deviation
  is documented in that chart.
- Charts are templated so that extension means adding templates and values, never forking or
  copying the shared foundation.
- The operator has administrative access to the GitHub organisation hosting both the repository and
  the registry. The repository is public, so the deployment agent reads it anonymously; a
  repository credential is supplied as an argument to the bootstrap command when one is needed,
  and is never committed and never held in the secret store.
- The delivered stack is a PostgreSQL database and a Redis cache, with Argo CD and Vault beneath
  them, plus an nginx reference chart. No business application is in scope: the end goal is a
  repository whose dependencies are running and whose charts are ready to be extended with real
  services. The foundation must not assume any particular application technology.
- Real services arrive later, as separate work. This feature is complete when a real service
  could be added by copying the reference chart and pointing it at the already-running database
  and cache. Nothing in this delivery waits on an application image.
- "Very minimal configuration" is a hard requirement on the charts, not a preference: anything a
  chart can reasonably infer or default MUST NOT be asked of the operator.
- Deferred to a later delivery and explicitly out of scope here: monitoring and alerting, log
  aggregation, and backup automation beyond stating each stateful component's backup expectations.
  The delivery relies on the cluster's built-in ingress and storage rather than installing its own
  ingress controller or certificate issuer.
- Vault's high availability, its storage backend's own durability, and automated unsealing are out
  of scope; a single-node Vault with manual unsealing on restart is accepted for the homelab.
- Configuration is carried in charts two ways: structured values the chart renders into the
  required format, and whole files carried verbatim so an `nginx.conf` or similar need not be
  escaped into YAML. A configuration change restarts its workload by default, because a workload
  that silently ignores a changed config is the more expensive failure.
- Database schema creation and migration are the future service's responsibility, not the
  charts'. The database chart creates the database and its role; everything inside it is the
  consuming service's concern.
- "Copy and paste" onboarding means copying a thin reference chart that delegates to the shared
  foundation — not copying an existing chart. The two look similar at the moment of copying but
  diverge immediately afterwards: a copied chart stops receiving convention changes and drifts,
  which is precisely the failure the foundation exists to prevent. The reference chart gives the
  same ergonomics without that cost.
- The audience for the onboarding guide is the operator themselves, months later, having forgotten
  the details — not a newcomer to Kubernetes. The guide assumes cluster familiarity but assumes no
  memory of how this repository works.
- There is exactly one reference chart, an nginx service, and it is a real deployed workload
  rather than an inert template. A chart that is continuously rendered, validated, and running
  cannot silently rot, which is what a separate scaffold directory risks. A service needing a
  shape the reference does not show — durable storage, a dependency reference — extends it using
  the mechanisms in the onboarding guide rather than selecting a different starting point.
