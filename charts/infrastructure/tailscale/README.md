# tailscale

Tailscale subnet router (hl-budget-spec feature 005, home and remote access). The owner's devices
signed in to their tailnet get a route to the homelab node's address, and only that address, so
`https://budget.valyalkin.com` and every other homelab app work away from home with **no port
open on the home router**. Installed by `bootstrap/install.sh` after `ingress-tls`.

How it works, the tailnet policy, and adding or removing a device: [`docs/remote-access.md`](../../../docs/remote-access.md).

## Design

- **Userspace networking** (`TS_USERSPACE=true`): no `NET_ADMIN`, no privileged init and no host
  network. The pod runs as UID 10001 with a read-only root filesystem, like every homelab
  workload. Traffic from the tailnet to `10.0.0.100` is dialled from the pod, and kube-proxy
  delivers it to Traefik's LoadBalancer address.
- **One StatefulSet replica**: two pods sharing one node identity would fight over it. A
  StatefulSet stops the old pod before starting the new one.
- **Identity in `Secret/tailscale-state`** (`TS_KUBE_SECRET`): restarts and upgrades keep the same
  machine, with no new registration. The pod creates the Secret on first start (Role: `create`
  on Secrets in this namespace, `get`/`update`/`patch` only on this one). Helm doesn't own it,
  so an uninstall keeps it. Delete it only to register the gateway afresh.
- **Credential**: a Tailscale OAuth client (scope *Auth Keys: Write*, tag `tag:homelab`) from
  Vault `kv/infra/tailscale` (key `client_secret`, role `edge`). At start it becomes a
  non-ephemeral, pre-approved auth key, and only first registration uses it. Tagged machines
  have no key expiry, so nobody signs in again periodically.
- **Policy dependency**: the tailnet policy must list `tag:homelab` in `tagOwners` and approve its
  route in `autoApprovers`. Otherwise the route waits for a click in the admin console.

## Storage, backup and restore

No volume. The node identity is the `tailscale-state` Secret; if it is lost the gateway simply
registers again as a new machine (remove the old one in the admin console).

## Deviation from the constitution

None. The Service on port 9002 exists because hl-common renders one per workload. It only serves
the health endpoint inside the cluster.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| hostname | string | `"homelab"` | Machine name in the tailnet admin console |
| routes | list | `[]` | REQUIRED: CIDRs this gateway advertises to the tailnet. Keep it to the homelab node only, so VPN devices cannot reach the rest of the home network. Example: `["10.0.0.100/32"]` |
| tags | list | `["tag:homelab"]` | REQUIRED: tags the gateway joins with. The OAuth client in Vault must be allowed to create keys for them, and the tailnet policy must list them in `tagOwners` and `autoApprovers` |
| tailscale.secrets.auth | object | `{"keys":{"client_secret":"TAILSCALE_OAUTH_SECRET"},"vaultPath":"infra/tailscale"}` | OAuth client secret (scope Auth Keys: Write, tag:homelab), written by the owner |
| tailscale.service | object | `{"ports":[{"name":"health","port":9002}]}` | Health endpoint only; the gateway makes outbound connections and serves nothing else |
| tailscale.workload.automountServiceAccountToken | bool | `true` | The pod stores its node identity in Secret `tailscale-state` through the Kubernetes API |
| tailscale.workload.command | list | `["/bin/sh","-c","export TS_AUTHKEY=\"${TAILSCALE_OAUTH_SECRET}?ephemeral=false&preauthorized=true\"; exec /usr/local/bin/containerboot"]` | The OAuth client secret becomes a non-ephemeral, pre-approved auth key at start (an OAuth secret alone would register an ephemeral node). The suffix is never stored anywhere. The variable is deliberately not TS_CLIENT_SECRET: containerboot treats that as its own OAuth mode and refuses it together with TS_AUTHKEY |
| tailscale.workload.env | list | `[{"name":"TS_USERSPACE","value":"true"},{"name":"TS_KUBE_SECRET","value":"tailscale-state"},{"name":"TS_SOCKET","value":"/tmp/tailscaled.sock"},{"name":"TS_ENABLE_HEALTH_CHECK","value":"true"},{"name":"TS_LOCAL_ADDR_PORT","value":"[::]:9002"},{"name":"HOME","value":"/tmp"}]` | Fixed containerboot settings; TS_ROUTES, TS_HOSTNAME and TS_EXTRA_ARGS come from the values above |
| tailscale.workload.image.digest | string | `"sha256:ed6480b33c6eb67c9cbd203ed42b9fb57e361986725b6856def71b7a3d9e276c"` |  |
| tailscale.workload.image.name | string | `"tailscale"` |  |
| tailscale.workload.image.owner | string | `"tailscale"` |  |
| tailscale.workload.image.registry | string | `"docker.io"` |  |
| tailscale.workload.image.tag | string | `"v1.104.4"` | Upstream version, pinned by digest |
| tailscale.workload.kind | string | `"StatefulSet"` | One pod, never two: two copies sharing one node identity would fight over it. A StatefulSet with one replica stops the old pod before starting the new one |
| tailscale.workload.probes.liveness.failureThreshold | int | `4` |  |
| tailscale.workload.probes.liveness.httpGet.path | string | `"/healthz"` |  |
| tailscale.workload.probes.liveness.httpGet.port | string | `"health"` |  |
| tailscale.workload.probes.liveness.periodSeconds | int | `30` |  |
| tailscale.workload.probes.readiness.httpGet.path | string | `"/healthz"` |  |
| tailscale.workload.probes.readiness.httpGet.port | string | `"health"` |  |
| tailscale.workload.probes.readiness.periodSeconds | int | `10` |  |
| tailscale.workload.probes.startup.failureThreshold | int | `60` |  |
| tailscale.workload.probes.startup.httpGet.path | string | `"/healthz"` |  |
| tailscale.workload.probes.startup.httpGet.port | string | `"health"` |  |
| tailscale.workload.probes.startup.periodSeconds | int | `5` |  |
| tailscale.workload.resources | object | `{"limits":{"memory":"128Mi"},"requests":{"cpu":"10m","memory":"48Mi"}}` | Memory limit; userspace networking for one route needs little |
| tailscale.workload.tmpDirs | list | `["/tmp"]` | Writable directories for the read-only root filesystem (socket, HOME) |
| vaultAuth | object | `{"createNamespace":false,"role":"edge"}` | Vault binding rendered by hl-common (ServiceAccount `tailscale` + VaultAuth, role `edge`) |
