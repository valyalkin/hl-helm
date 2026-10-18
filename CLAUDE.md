# hl-helm — agent guidance

Helm charts for a single-node k3s homelab. This file stays consistent with
`.specify/memory/constitution.md`; where they conflict, the constitution wins.

## Layout

- `charts/library/hl-common` — the shared foundation (library chart). All naming, labels, probes,
  limits, security context, TLS ingress, image rules, secrets and storage live here.
- `charts/bootstrap/` (Vault, Argo CD) and `charts/infrastructure/` (VSO, CloudNativePG, Postgres,
  Redis) are applied by `bootstrap/install.sh`. `charts/apps/` is applied by Argo CD from `main`.
  Argo CD never manages the first two.
- `charts/apps/nginx` is the reference chart and copy source. One application = one chart = one
  namespace named for its directory.
- `specs/001-extensible-helm-charts/` — spec, plan, tasks, contracts. `tasks.md` is the status.

## Rules that bite

- Run `scripts/validate.sh` before committing; `scripts/validate.sh --self-test` after touching
  the gate. After editing `hl-common`, charts that consume it need `helm dependency update`.
- Never put secret material in the repo (not even in tests). Charts carry Vault paths only.
- A bootstrap-tier chart may not declare a secret reference.
- Bump a chart's `version` whenever its templates or defaults change (CI checks).
- Never copy a template out of `hl-common`; extend through the three sanctioned mechanisms
  (`charts/library/hl-common/README.md`).
- Images: version tag or digest, never `latest`. Every container needs a memory limit.
- Infrastructure changes reach the cluster only through `bootstrap/install.sh`; review with
  `--diff` first and apply from a committed tree.
- Change anything an operator sets → update `docs/onboarding.md` and the reference chart together.

## Tooling

`helm` (4.x; validated on 4.1.1, as in CI), `helm-unittest` (`helm unittest -f '*_test.yaml' tests/unit`), `kubeconform`,
`helm-docs` (commit its output), `python3` + PyYAML for `tests/policy/`, `k3d` for a disposable
cluster. Docs: `docs/onboarding.md`, `docs/bootstrap.md`, `docs/tiers.md`,
`docs/validation-results.md`.
