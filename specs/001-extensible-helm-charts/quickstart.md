# Quickstart: Validating the Homelab Chart Repository

**Feature**: 001-extensible-helm-charts | **Date**: 2026-10-16

Runnable scenarios that prove the feature works. Each maps to success criteria in
[spec.md](./spec.md). Run them in order the first time; afterwards they are independent.

## Prerequisites

| Tool | Purpose |
|------|---------|
| `helm` 4.x (validated on 4.1.1; CI uses the same) | Rendering and the one bootstrap install |
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
scripts/validate.sh
```

Runs, in order: `helm lint` on every chart → `helm template` against each chart's `ci/` values →
`kubeconform` (with the CRD catalog) → `helm unittest` → the policy checks in `tests/policy/` →
the `helm-docs` staleness check. **Expected**: `GATE PASS`.

The gate is only worth something if it fails when it should:

```bash
scripts/validate.sh --self-test
```

Injects eight violations (mutable tag, embedded dependency, secret literal, bootstrap secret
reference, missing version bump, missing memory limit, unchanged placeholder, duplicate ingress
host). **Expected**: `8 of 8 violations caught`, each naming the file and value.

---

## Step 2 — Bootstrap an empty cluster

Proves SC-018 and SC-030 — exactly one manual command.

```bash
bootstrap/install.sh [--context <ctx>] [--keys-file <path>] [--repo-credential <file>]
```

**Expected**: Vault, Vault Secrets Operator, CloudNativePG, Postgres and Redis installed in that
order (each waited on), Vault initialised, unsealed and configured by the script, then Argo CD and
the ApplicationSet, which discovers `charts/apps/*`. The repository is public, so the credential is
optional (research R-007).

```bash
kubectl -n argocd get applications
```

**Expected**: `nginx` `Synced` and `Healthy`.

## Step 3 — Keep Vault's unseal material

`bootstrap/vault-init.sh` (run by `install.sh`) writes the unseal key and root token to
`~/.hl-helm/vault-init.json`, outside the repository. **Copy it to a password manager now.** After
a node restart Vault is sealed; run `bootstrap/vault-init.sh` again to unseal it (`docs/bootstrap.md`).

The bootstrap tier came up before Vault held any data, confirming nothing in it depends on Vault
(FR-056).

## Step 4 — Confirm the infrastructure report

```bash
scripts/infra-status.sh [--context <ctx>]
```

**Expected**: every release `deployed`, repository and deployed versions equal, drift `none`.
(Argo CD does not manage these releases, so there is no Argo CD application to check.)

## Step 5 — Prove the stack is ready for real services

Proves SC-020 and SC-036.

```bash
curl -kI --resolve <nginx-host>:443:<node-ip> https://<nginx-host>/                                  # reference service over TLS
kubectl -n postgres get cluster postgres                         # Cluster in healthy state
kubectl -n postgres get database                                 # the nginx database: applied true
kubectl -n redis get pods
kubectl -n vault exec vault-0 -- env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=<root> \
  vault kv get kv/apps/nginx/postgres                            # the credential exists
kubectl -n vault exec vault-0 -- env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=<root> \
  vault kv get kv/infra/redis
```

**Expected**: nginx serves over TLS; Postgres is healthy with the `nginx` database and role; Redis
responds to an authenticated `PING`; both credentials resolve in Vault. A real service is then
added by copying `charts/apps/nginx/` (`docs/onboarding.md`) with no change to any infrastructure
chart other than a line in `bootstrap/values/postgres.yaml` for its database.

## Step 6 — Prove decoupling

Proves SC-031, SC-032, SC-034.

```bash
# Applications come and go; dependencies do not notice.
for i in $(seq 1 10); do
  kubectl -n nginx delete deployment nginx-web
  # Argo CD (selfHeal) recreates it; wait for it to exist, then for the rollout. Repeated
  # deletions raise self-heal's exponential backoff (cap ~3 min), so allow for that.
  until kubectl -n nginx get deploy nginx-web >/dev/null 2>&1; do sleep 3; done
  kubectl -n nginx rollout status deploy/nginx-web --timeout=120s
done
kubectl -n postgres get pod postgres-1 -o jsonpath='{.metadata.uid} {.status.containerStatuses[0].restartCount}'
```

**Expected**: the Postgres pod UID and restart count are unchanged and its data intact (SC-031).

```bash
# A dependency upgrade leaves applications alone: bump the Redis image, then
bootstrap/install.sh --only redis --diff   # review
bootstrap/install.sh --only redis
kubectl -n nginx get pods -o jsonpath='{.items[*].metadata.creationTimestamp}'
```

**Expected**: unchanged timestamps (SC-032).

```bash
# Infrastructure stands alone.
helm template charts/infrastructure/postgres -f charts/infrastructure/postgres/ci/default-values.yaml
```

**Expected**: valid with no application present (SC-034).

---

## Step 7 — Prove secret rotation

Proves SC-016 and FR-028. Redis consumes `kv/infra/redis`:

```bash
kubectl -n vault exec vault-0 -- env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=<root> \
  vault kv put -mount=kv infra/redis password=<new>
kubectl -n redis get pods -w
```

**Expected**: within `refreshAfter` (default 1h) the Secret updates and VSO restarts Redis. No
chart changed.

## Step 8 — Prove drift correction

Proves SC-015 and FR-031.

```bash
kubectl -n nginx scale deployment nginx-web --replicas=5
# Self-heal is not instant; allow up to 10 minutes (SC-015). A single change usually reverts in
# seconds, but it can take ~4 min after repeated heals (the step 6 loop).
until [ "$(kubectl -n nginx get deployment nginx-web -o jsonpath='{.spec.replicas}')" = 1 ]; do sleep 5; done
```

**Expected**: back to the repository's value (1).

## Step 9 — Prove onboarding

Proves SC-023, SC-024, SC-027 — the hardest to fake, because the measurement is a person. Follow
`docs/onboarding.md` to add a service, timing it and counting every lookup beyond the guide.

**Expected**: under 15 minutes (SC-023), at most 10 parameters changed (SC-024), zero lookups
outside the guide (SC-025). Adding an application needs no Argo CD manifest — the generator finds
the directory. A change to a default in `hl-common` shows up in the copied chart's render without
editing it (SC-027).
