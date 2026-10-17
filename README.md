# hl-helm

Helm charts that define and maintain a single-node k3s homelab. The repository is the source of
truth: the cluster can be rebuilt from an empty node with `bootstrap/install.sh`.

## Tier model

| Tier | Directory | Applied by | Members |
|------|-----------|-----------|---------|
| Library | `charts/library/` | consumed by other charts | `hl-common` |
| Bootstrap | `charts/bootstrap/` | `bootstrap/install.sh` | Vault, Argo CD |
| Infrastructure | `charts/infrastructure/` | `bootstrap/install.sh` | Vault Secrets Operator, CloudNativePG, Postgres, Redis |
| Application | `charts/apps/` | Argo CD, auto-sync from `main` | one chart per application; `nginx` is the reference |

Start with [`docs/onboarding.md`](docs/onboarding.md) to deploy an application,
[`docs/bootstrap.md`](docs/bootstrap.md) to rebuild the cluster, and [`docs/tiers.md`](docs/tiers.md)
for what each tier may depend on. Measured results are in
[`docs/validation-results.md`](docs/validation-results.md).

See `specs/001-extensible-helm-charts/` for the specification, plan and tasks, and
`.specify/memory/constitution.md` for governance.

## Cluster baseline

- k3s version: _to be recorded at quickstart step 0 (task T005)_
- Storage classes: _pending_
- Ingress: Traefik (k3s built-in) — _pending confirmation_

## Validation

`scripts/validate.sh` runs the pre-merge gate (lint, template, unit tests, schema validation).
