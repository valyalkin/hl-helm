# Tiers

Charts are grouped by what they depend on, and the grouping is the directory layout.

| Tier | Directory | May depend on | Applied by | Members |
|------|-----------|---------------|-----------|---------|
| Bootstrap | `charts/bootstrap/` | nothing in the cluster | `bootstrap/install.sh` | Vault, Argo CD |
| Infrastructure | `charts/infrastructure/` | bootstrap | `bootstrap/install.sh` | Vault Secrets Operator, CloudNativePG, Postgres, Redis |
| Application | `charts/apps/` | bootstrap, infrastructure | Argo CD, auto-sync from `main` | one chart per application (`nginx` is the reference) |

`charts/library/hl-common` is consumed by charts, not deployed.

## Rules

- **No bootstrap component reads from Vault.** Vault is installed first and is empty and sealed
  when it starts; a bootstrap chart that needed a secret would deadlock a cold rebuild. CI fails
  any bootstrap chart that declares a secret reference (FR-056).
- **Argo CD manages the application tier only.** The ApplicationSet's generator looks under
  `charts/apps/` and nowhere else, so a merge can never restart a data service. Infrastructure
  changes reach the cluster only when an operator runs `bootstrap/install.sh`.
- **Applications do not embed their dependencies.** An application chart depends only on
  `hl-common`; it reaches Postgres or Redis through an address supplied as configuration, so the
  two lifecycles never touch (FR-066, FR-069).
- **One application, one chart, one namespace.** The chart renders its own Namespace,
  ServiceAccount and Vault binding; the directory name is the namespace.

## Reporting infrastructure state

Argo CD does not watch the bootstrap and infrastructure tiers, so this is the report to run
regularly (FR-034, SC-017):

```sh
scripts/infra-status.sh [--context <ctx>]
```

For every release in `bootstrap/install-order.yaml` it shows the deployed chart version, the
repository's version, the release status, and — when `helm-diff` is installed — `DRIFT` if the live
objects differ from what the repository would apply (a hand-edited replica count, for instance).
It also lists any unhealthy pod in the infrastructure namespaces. Act on `DRIFT` by reviewing
`bootstrap/install.sh --only <name> --diff` and re-applying.
