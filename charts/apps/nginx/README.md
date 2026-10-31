# nginx

Reference application chart — a running nginx service and the directory operators copy to onboard a new application.

This chart is **both** a running service (nginx, deployed by Argo CD into the `nginx` namespace)
**and** the copy source for onboarding a new application: copy the directory, rename it, set the
parameters marked `REQUIRED` in `values.yaml`. See [`docs/onboarding.md`](../../../docs/onboarding.md).

Because it is deployed continuously and rendered by CI on every change, it cannot drift from the
shared foundation unnoticed.

For extension examples beyond one stateless service — durable storage, dependency references,
custom resources — see `charts/infrastructure/postgres/` and `charts/infrastructure/redis/`, and
the extension guide in `charts/library/hl-common/README.md`.

## Image

`nginxinc/nginx-unprivileged:alpine` pinned by digest, in place of `nginx:alpine`: the shared
security defaults run every container non-root with a read-only root filesystem, which the stock
nginx image cannot do.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| web.ingress.enabled | bool | `true` | OPTIONAL: expose the service over TLS. Example: `true` |
| web.ingress.host | string | `"nginx.valyalkin.com"` | REQUIRED when ingress is enabled: hostname, one label under valyalkin.com, unique across charts. The wildcard DNS record and certificate already cover it; leave `tls` unset so Traefik serves the shared certificate. Example: `todo.valyalkin.com` |
| web.service | object | `{"ports":[{"name":"http","port":80,"targetPort":8080}]}` | REQUIRED: the ports the service exposes. Example: `[{name: http, port: 80, targetPort: 8080}]` |
| web.workload.image.digest | string | `"sha256:378d0c32f6562f7fd9629170797f57d2b953aa09be983b3daaf4809bb039ca00"` | OPTIONAL: pins the image by digest; wins over the tag. Example: `sha256:3782...` |
| web.workload.image.name | string | `"nginx-unprivileged"` | REQUIRED: image name, without registry or owner. Example: `todo-backend` |
| web.workload.image.owner | string | `"nginxinc"` | OPTIONAL: registry owner; defaults to this repository's owner. Example: `nginxinc` |
| web.workload.image.registry | string | `"docker.io"` | OPTIONAL: registry; defaults to `ghcr.io`. Upstream images set it. Example: `docker.io` |
| web.workload.image.tag | string | `"alpine"` | REQUIRED: a version tag (never `latest`) or a digest. Example: `1.4.2` |
| web.workload.resources | object | `{"limits":{"memory":"64Mi"}}` | REQUIRED: memory limit — there is no default on a shared node. Example: `128Mi` |
| web.workload.tmpDirs | list | `["/tmp"]` | OPTIONAL: writable directories for the read-only root filesystem. Example: `[/tmp]` |
