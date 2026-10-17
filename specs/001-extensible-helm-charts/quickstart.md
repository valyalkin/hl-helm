# Quickstart: Validating the Homelab Chart Repository

**Feature**: 001-extensible-helm-charts | **Date**: 2026-10-16

Runnable scenarios that prove the feature works. Each maps to success criteria in
[spec.md](./spec.md). Run them in order the first time; afterwards they are independent.

## Prerequisites

| Tool | Purpose |
|------|---------|
| `helm` 3.16+ | Rendering and the one bootstrap install |
| `kubectl` with a kubeconfig for the node | Everything cluster-side |
| `helm-unittest` plugin | Library chart template tests |
| `kubeconform` | Rendered-manifest schema validation |
| `helm-docs` | README generation and drift check |
| `python` 3.11 | Repository policy checks |

---

## Step 0 — Record the cluster's baseline

Resolves the one unverified item in [research.md](./research.md) (R-010). Everything downstream
validates against these facts, so this comes first. Requires a kubeconfig for the node.

```bash
kubectl version -o json | jq -r '.serverVersion.gitVersion'   # → root README.md
kubectl get storageclass                                       # expect local-path
kubectl get pods -A | grep -iE 'traefik|servicelb'             # expect Traefik present
kubectl get pods -A | grep -iE 'vault|postgres'                # locate instances to be cleared
```

**Expected**: a version string written into the root `README.md` and into the
`--kubernetes-version` flag `kubeconform` uses in CI, so validation and the cluster cannot drift
apart. If the version is below 1.31, check CloudNativePG 1.30's minimum before going further — it
is the binding constraint. If Traefik is absent or disabled, R-008's TLS decision needs revisiting
before any chart is written.

---

## Step 1 — Validate the whole repository without a cluster

Proves Principle III's gate and SC-006. Requires no cluster at all.

```bash
make validate     # or: scripts/validate.sh
```

Which runs, in order: `helm lint` on every chart → `helm template` against each chart's `ci/`
values files → `helm unittest` on `hl-common` → `kubeconform` on all rendered output → the four
policy checks → `helm-docs` with a dirty-tree check.

**Expected**: all green, exit 0. **Negative check** — the gate is only worth something if it
fails when it should:

```bash
scripts/validate.sh --self-test
```

Deliberately injects each of: a mutable image tag, a missing `limits.memory`, an unchanged
unchanged placeholder, a duplicate ingress host, a secret-shaped literal, and an application chart
depending on an infrastructure chart. **Expected**: six failures, each naming the offending file
and value (SC-006, SC-007, SC-008, SC-033).

---

## Step 2 — Bootstrap an empty cluster

Proves SC-018 and SC-030 — exactly one manual command.

```bash
./bootstrap/install.sh --repo-credential <token-or-key-path>
```

The repository is public, so Argo CD can read it anonymously and the credential is optional. Pass
it to avoid anonymous GitHub rate limits during a cold rebuild, and whenever Argo CD needs write
access. It is written straight into the Argo CD repository Secret and persisted nowhere else —
never committed, never read from Vault (research R-007).

**Expected**: the infrastructure tiers are installed in order, then Argo CD, then
`argocd/applicationset.yaml`, which discovers every application chart under `charts/apps/*`.
Nothing else is run by hand.

```bash
kubectl -n argocd get applications -w
```

**Expected**: applications appear and sync in wave order — Argo CD, Vault, then VSO and the CNPG
operator, then Postgres and Redis, then the nginx reference service.

---

## Step 3 — Initialise and unseal Vault

The one place a human holds material that is never committed (FR-059).

```bash
kubectl -n vault exec -it vault-0 -- vault operator init -key-shares=1 -key-threshold=1
kubectl -n vault exec -it vault-0 -- vault operator unseal <key>
```

**Expected**: Vault unsealed. **Store the unseal key and root token outside the cluster now** — a
password manager, not this repository. Then seed the database and cache secrets and the Kubernetes auth role
per `docs/bootstrap.md`.

**Verify the tier rule** (FR-056): the bootstrap tier came up *before* this step, confirming
nothing in it depended on Vault.

---

## Step 4 — Confirm Argo CD adopted its own release

Closes the risk recorded in research R-007.

```bash
kubectl -n argocd get application argocd -o jsonpath='{.status.sync.status}'
```

**Expected**: `Synced` with an empty diff. A non-empty diff means the imperative install and the
declarative Application disagree — reconcile the values file before going further, or every later
sync carries the discrepancy.

---

## Step 5 — Prove the stack is ready for real services

Proves SC-020 and SC-036.

```bash
curl -kI https://<nginx-host>/                                   # reference service reachable
kubectl -n database get cluster postgres -o jsonpath='{.status.readyInstances}'
kubectl -n cache get pods -l app=redis
```

Then confirm each dependency is genuinely consumable, which is the point of this delivery:

```bash
# The application database and role exist, and the credential is in Vault.
kubectl -n database exec -it postgres-1 -- psql -U postgres -c '\du'
kubectl -n vault exec -it vault-0 -- vault kv get secret/database/app
```

**Expected**: nginx serves over TLS; Postgres reports its instance ready with the application
database and role present; Redis responds; and both credentials resolve in Vault. At that point a
real service can be added by copying `charts/apps/nginx/` and pointing it at these addresses —
with no change to any infrastructure chart.

---

## Step 6 — Prove decoupling

Proves SC-031, SC-032, SC-034 — the requirements most easily lost in implementation.

```bash
# Applications come and go; dependencies do not notice.
for i in $(seq 1 10); do
  kubectl -n nginx delete deployment nginx-web
  argocd app sync nginx --timeout 120
done
kubectl -n database get cluster postgres -o jsonpath='{.status.readyInstances}'
```

**Expected**: Postgres reports ready throughout, its restart count unchanged, its data intact
(SC-031).

```bash
# A dependency upgrade leaves applications alone.
# Bump the Redis image in charts/infrastructure/redis, merge, then:
kubectl -n nginx get pods -o jsonpath='{.items[*].metadata.creationTimestamp}'
```

**Expected**: unchanged timestamps — no application was redeployed (SC-032).

```bash
# Infrastructure stands alone.
helm template charts/infrastructure/postgres | kubectl apply --dry-run=server -f -
```

**Expected**: valid with no application present (SC-034).

---

## Step 7 — Prove secret rotation

Proves SC-016 and FR-028.

```bash
# Rotate in Vault, then watch the consumer.
kubectl -n nginx get pods -w
```

**Expected**: the `VaultStaticSecret` refreshes within `refreshAfter`, and the consuming
workload is restarted automatically by VSO's rollout target. No chart changed.

---

## Step 8 — Prove drift correction

Proves SC-015 and FR-031.

```bash
kubectl -n nginx scale deployment nginx-web --replicas=5
sleep 60
kubectl -n nginx get deployment nginx-web -o jsonpath='{.spec.replicas}'
```

**Expected**: back to the repository's value, with the drift reported in Argo CD.

---

## Step 9 — Prove onboarding

Proves SC-023, SC-024, SC-027 — the hardest to fake, because the measurement is a person.

Follow `docs/onboarding.md` to add a new service, timing it and counting every time you look
beyond the guide.

**Expected**: under 15 minutes (SC-023), no more than 10 parameters changed (SC-024), zero
lookups outside the guide (SC-025).

```bash
# Adding an application needs no Argo CD manifest — the generator finds the directory.
# Copy charts/apps/nginx to charts/apps/demo, rename it, commit, then:
kubectl -n argocd get applications

# The copied chart inherited conventions rather than copying them.
# Change a default in hl-common, then:
helm template charts/apps/<new-service> | grep -A3 'resources:'
```

**Expected**: the new chart picks up the foundation change without being edited (SC-027).
