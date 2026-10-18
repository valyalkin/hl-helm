# Validation results

Measured outcomes against the success criteria of `specs/001-extensible-helm-charts/spec.md`.
**Environment**: a disposable local `k3d` cluster (k3s, single server, Traefik and `local-path`
present), Helm 4.1.1, on an Apple-silicon workstation, with an in-cluster Git server standing in
for GitHub. The *Real server* section below records the run against the homelab node (k3s
v1.36.5, Ubuntu 26.04, Helm 4.1.1 client) on 2026-10-18.

## Timings

| Criterion | Measure | Result |
|-----------|---------|--------|
| SC-005 rebuild from empty node | empty cluster → every component deployed and applications `Synced`/`Healthy` | ~4 min 15 s on k3d (target < 2 h). |
| SC-014 merge-to-cluster latency | push to Git → new application running | ~45 s with a forced refresh; Argo CD polls every 180 s (`bootstrap/argocd-values.yaml`), so worst case ≈ 3 min + sync (target < 10 min) |
| SC-015 drift correction | `kubectl scale` by hand → repository value restored | 3 s |
| SC-016 secret rotation | rotate in Vault → Secret updated → consumer restarted | Secret updated in 12 s and pod restarted by 16 s with `refreshAfter: 15s`; the shipped default is `1h` (target ≤ 1 h) |
| SC-020 stack ready | covered by SC-005: reference service, database and cache healthy within the same ~4 min | |
| SC-023 onboarding time | a person following `docs/onboarding.md` alone | **Not measured independently.** An implementer dry run took ~2 min of tool time and exercised the guide; it is not a valid SC-023 sample because it was not performed by someone who had not read the foundation |

## Real server (2026-10-18)

| Criterion | Result |
|-----------|--------|
| SC-005 rebuild from empty node | `bootstrap/install.sh` on a fresh k3s node: Vault, VSO, CloudNativePG, Postgres, Redis, Argo CD and the ApplicationSet in ~2 min (first pod created 11:37:59, script finished 11:39:48 local); nginx `Synced`/`Healthy` ~3 min after the branch reached `main` (target < 2 h) |
| SC-014 merge-to-cluster latency | merge into `main` → `nginx` Application created and pod `Running` in ~3 min, bounded by the 180 s poll (target < 10 min) |
| SC-015 drift correction | `kubectl scale --replicas=5` was reverted after ~4 min, not 3 s. It followed ten rapid delete/recreate cycles, which push Argo CD's self-heal backoff towards its 3 min cap, so this is a worst case. Within the 10 min target |
| SC-020 stack ready | Postgres `Cluster in healthy state`, `nginx` database `applied: true`, Redis answering an authenticated `PING`, both credentials in Vault at version 1, nginx HTTPS 200 |
| SC-031 | `nginx-web` deleted ten times; `postgres-1` UID and restart count (0) unchanged |
| SC-036 | credentials `kv/apps/nginx/postgres` and `kv/infra/redis` exist in Vault; VSO synced both Secrets |
| TLS | Traefik's built-in self-signed certificate (research R-008); plain HTTP returns 404 rather than redirecting |

Self-heal timing: deleting `nginx-web` once was recreated in 41 s; ten deletions in a row took
670 s, and four cycles missed the 2 min wait. Argo CD backs off exponentially between self-heals.

## Counted criteria

| Criterion | Result |
|-----------|--------|
| SC-002 / SC-019 lines of configuration per chart | `nginx` values.yaml: 16 non-comment lines (within the 20-line budget). `redis`: 37 — **over budget**: about 14 of those lines are the Vault provisioning block and 7 the image/command, which are infrastructure-specific rather than boilerplate; SC-019 is met for the application tier and not for `redis` |
| SC-024 parameters changed when onboarding | 7 in the dry run: image name, tag (and digest removed), owner, memory limit unchanged, ports unchanged, host, `args` (this image needed a flag) |
| SC-025 lookups outside the guide | 2 in the dry run — that `helm-docs` output must be committed, and how to pass container arguments; both are now in the guide |
| SC-006 invalid input caught | `scripts/validate.sh --self-test` injects 8 violations (mutable tag, embedded dependency, secret literal, bootstrap secret, missing version bump, missing memory limit, unchanged placeholder, duplicate host); 8 of 8 caught, each naming file and value |
| SC-007 / SC-008 | policy checks 3 and 1 run on every change in CI |

## Verified on k3d

| Criterion | How |
|-----------|-----|
| SC-011 / US1 idempotence | `helm upgrade` twice on `nginx`: every resource version unchanged |
| SC-010 / SC-022 | `helm uninstall postgres` then reinstall: row written before is still there. `helm upgrade` then `helm rollback` of `postgres`: data intact |
| SC-027 / SC-003 | edited a default in `hl-common`; `nginx` rendered the new value with no edit to the chart (charts that set their own value, like `redis`, keep it by design) |
| SC-031 | `nginx` created and deleted 10 times; the Postgres pod's UID, restart count and start time were unchanged and its data intact |
| SC-032 | bumped the Redis image: the `nginx` pod UID was unchanged while Redis's changed |
| SC-033 | policy check 2; also self-test case 2 |
| SC-034 | each of Vault, Vault Secrets Operator, CloudNativePG, Postgres and Redis installed on an empty k3d cluster with no application present |
| SC-018 / SC-030 | one command (`bootstrap/install.sh`); Vault initialised, unsealed and configured by the script |
| FR-045 | a new `charts/apps/<name>` directory was deployed into its own namespace by Argo CD with no manifest written; removing it pruned the Application and namespace |
| Sealed Vault | restarting Vault leaves it sealed; Redis, Postgres and nginx kept running; `bootstrap/vault-init.sh` unsealed it and VSO resumed syncing |

## Not verified

- SC-035 (an application started before its dependencies becomes ready on its own) — not run.
- SC-012 / SC-028 documentation coverage — values tables are generated by `helm-docs`, but coverage
  is not measured mechanically; undocumented values show a blank description.
- SC-013, SC-001, SC-004, SC-009, SC-017 are satisfied by construction or by process but have not
  been separately measured.
- SC-032 and SC-016 on the real server (a Redis image bump and a credential rotation were skipped to avoid changing live state); both were verified on k3d.
- SC-023/SC-024/SC-025 (T078): needs a person to time an onboarding run.
