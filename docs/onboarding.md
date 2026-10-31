# Onboarding

From "I have a service" to a deployed service. You do not need to read the foundation
(`charts/library/hl-common`) to follow this.

An **application** is one chart in `charts/apps/<name>/`. It deploys every **service** the
application is made of (a frontend, a backend, …) into one namespace named `<name>`. Argo CD
discovers the directory on its own — there is no deployment manifest to write.

## A. Deploy a new application

1. **Copy the reference chart.** `charts/apps/nginx/` is a real, running service and the copy
   source.

   ```sh
   cp -R charts/apps/nginx charts/apps/todo
   rm -rf charts/apps/todo/charts charts/apps/todo/Chart.lock
   ```

2. **Rename it.** In `charts/apps/todo/Chart.yaml` set `name: todo` (it must equal the directory,
   which becomes the namespace). Leave the two `hl-common/…` annotations alone: renaming the chart
   switches on the placeholder guard, so rendering fails — naming the parameter — until step 3 is
   done. Delete `charts/apps/todo/README.md.gotmpl` (it describes the reference chart); `helm-docs`
   generates a fresh `README.md` from your values comments in step 4.

3. **Set the parameters** in `charts/apps/todo/values.yaml`. Every one is marked `REQUIRED` or
   `OPTIONAL` in place, with its purpose and an example:

   | Parameter | What to put |
   |-----------|-------------|
   | `web.workload.image.name` | your image's name, without registry or owner |
   | `web.workload.image.tag` / `digest` | a version tag, or a digest. `latest` is rejected |
   | `web.workload.image.registry` / `owner` | delete both to use `ghcr.io/<this repo's owner>` |
   | `web.workload.resources.limits.memory` | a memory limit; there is no default |
   | `web.service.ports` | the port(s) the container listens on |
| `web.workload.args` / `tmpDirs` | only if your image needs flags or writable directories (the root filesystem is read-only) |
   | `web.ingress.host` | `<name>.valyalkin.com`: one label under the domain, unique across charts (a clash fails CI) |

   Probes, security context, resource requests, labels and TLS are filled in for you. Leave
   `web.ingress.tls` unset: Traefik then serves the shared `*.valyalkin.com` certificate, and the
   wildcard DNS record already points every name at the node, so a new app needs **no DNS or
   certificate step**. The app is private: reachable at home and over Tailscale, not from the
   internet ([`remote-access.md`](remote-access.md)).

4. **Check it locally.**

   ```sh
   helm dependency update charts/apps/todo
   helm template todo charts/apps/todo | less        # read what you are about to deploy
   helm-docs                                         # generate the chart README; commit it
   scripts/validate.sh                               # the same gate CI runs
   ```

5. **Open a pull request.** CI runs the gate and posts the rendered diff to the job summary;
   paste it into the description. **Merging deploys it**: Argo CD (polling every three minutes)
   creates the `todo` namespace and everything in it. Watch with
   `kubectl -n argocd get applications`.

## B. Add a service to an existing application

Inside that application's chart only — nothing outside it changes.

1. Add a block to `values.yaml`, named for the service (copy the `web:` block).
2. Add `templates/<service>.yaml` containing one line, with the same name:

   ```yaml
   {{ include "hl-common.all" (dict "root" . "name" "api" "values" .Values.api) }}
   ```

3. Validate and open a pull request as above. The new service shares the application's namespace
   and can reach its siblings by short name (`<release>-<service>`).

## C. Releasing from a service repository

Each service lives in its own repository and builds its own image. A file at that repository's
root links it to its place here:

```yaml
# homelab.yaml in the service repository
app: todo          # charts/apps/todo
service: api       # the `api:` block and templates/api.yaml
image: todo-api    # ghcr.io/<owner>/todo-api
```

On every push to its `main`, the service's release workflow pushes the image as
`ghcr.io/<owner>/<image>:<run>-<sha>`, checks out this repository and runs

```sh
scripts/bump-image.py <app> <service> <tag> <digest>
```

which pins the new tag and digest in `charts/apps/<app>/values.yaml`, bumps the chart's patch
version and regenerates its README. The workflow then opens a pull request here. CI runs the gate
and the rendered diff as for any change, and **merging deploys the new version**.

The script only changes an image. A new application or a new service block is still a reviewed
chart change (sections A and B), made once with the first image's digest. After that, the bump
fails and names what is missing if the block is gone.

The workflow needs a repository secret `HL_HELM_TOKEN`: a fine-grained personal access token
limited to this repository, with *Contents* and *Pull requests* read and write. A pull request
opened with the workflow's own `GITHUB_TOKEN` would not trigger CI here. Until the secret is set, the
workflow still pushes the image and ends with a warning instead of a pull request.

## Secrets

Secrets live in Vault and never in this repository. Put the value at
`kv/apps/<namespace>/<anything>` — an application can read only its own namespace's path — then
reference it from the service block:

```yaml
web:
  secrets:
    db:
      vaultPath: apps/todo/db                  # path under the kv mount
      keys: {password: DB_PASSWORD}            # Vault key -> environment variable
```

The operator syncs it into a Kubernetes Secret, injects the variable, and **restarts the workload
when the value changes** (rotation needs no chart change). No chart can hold the value itself; CI
rejects secret-shaped literals.

## Images

Images default to `ghcr.io/<this repository's owner>/<name>`. Set `registry` and `owner` for an
upstream image. Every image needs a version tag or a digest — `latest` and bare tags fail
rendering.

Application images on ghcr.io are **public**, so no pull credential is needed. ghcr creates each
new package as private: make it public once, at
`https://github.com/users/<owner>/packages/container/<name>/settings` → *Change visibility*. Until
then the pod fails with `ImagePullBackOff`.

If one image must stay private, store a registry credential in Vault under the application's own
path (the `apps` policy grants nothing else) as a `kubernetes.io/dockerconfigjson` secret entry,
and name it in `image.pullSecret`:

```yaml
web:
  workload: {image: {pullSecret: ghcr}}
  secrets:
    ghcr: {vaultPath: apps/todo/ghcr, type: kubernetes.io/dockerconfigjson}
```

## Databases and the cache

Your application reaches Postgres and Redis through addresses it is given as configuration, so
neither lifecycle touches the other. To get a database, add `- name: todo` to `databases:` in
`bootstrap/values/postgres.yaml` and apply it (`bootstrap/install.sh --only postgres`); a
credential is generated in Vault at `kv/apps/todo/postgres`. Postgres names cannot contain a
hyphen, so an application in namespace `my-app` adds `{name: my_app, namespace: my-app}`: the
database and role are `my_app` and the credential still lands at `kv/apps/my-app/postgres`.
Then declare it:

```yaml
web:
  dependencies:
    postgres:
      host: postgres-rw.postgres.svc.cluster.local
      port: 5432
      credentials: {vaultPath: apps/todo/postgres, keys: {username: POSTGRES_USER, password: POSTGRES_PASSWORD}}
    redis:
      host: redis.redis.svc.cluster.local
      port: 6379
      optional: true          # the cache is an accelerator: degrade, do not fail
      credentials: {vaultPath: infra/redis, keys: {password: REDIS_PASSWORD}}
```

Connection details for each dependency are in `charts/infrastructure/postgres/README.md` and
`charts/infrastructure/redis/README.md`. Your service reads `POSTGRES_HOST`, `POSTGRES_PORT`,
`POSTGRES_OPTIONAL` (and the same for `REDIS_`) from its environment. Make its readiness endpoint
fail while a *required* dependency is unreachable, so Argo CD's health reflects reality.

## Extending beyond the reference chart

The reference chart covers one stateless service behind TLS. For anything else there are exactly
three sanctioned ways, each with a worked example in
[`charts/library/hl-common/README.md`](../charts/library/hl-common/README.md):

1. **Add a resource** — drop an ordinary manifest in `templates/` and use `hl-common.name` /
   `hl-common.labels` so it matches (a CronJob, a sidecar-less worker).
2. **Override a default** — set it in `values.yaml`.
3. **Replace a rendered section** — opt in with `overrides.<section>: true` and define
   `<chart>.override.<section>`; record why in the chart's README.

Two shapes the reference chart does not show, with real deployed examples:

- **Durable storage** (`storage:` with an explicit `storageClassName`, a StatefulSet): see
  `charts/infrastructure/postgres/` for a retained volume and its backup note.
- **Dependency references and secrets**: the snippets above, and `charts/infrastructure/redis/`,
  which is itself built on the same library.

Never copy a template out of `hl-common`: a copy stops receiving convention changes, and CI fails
it.

## Previewing a change before it merges

No staging cluster exists, so a human reviews the rendered diff before a change becomes real.

- **Application tier** (anything under `charts/apps/`): merging deploys it. CI renders the diff
  between `main` and your branch into the pull request's job summary. Read it, and paste it into
  the change description.
- **Infrastructure and bootstrap tiers**: a merge changes nothing on the cluster. Before applying,
  preview against the running release:

  ```sh
  helm plugin install https://github.com/databus23/helm-diff   # once
  bootstrap/install.sh --only <release> --diff
  ```

  Record the output in the change description, then apply from a committed state only.

Run `scripts/validate.sh` locally first; it is the same gate CI enforces.

See also [`docs/tiers.md`](tiers.md), [`docs/bootstrap.md`](bootstrap.md) and the repository [`README.md`](../README.md).
