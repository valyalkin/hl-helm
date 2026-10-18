# Accessing the cluster from your workstation

The k3s API and every service in the cluster are reachable only from the node itself. From your
workstation you get to them through SSH. Nothing here opens a port on your network, and nothing
here changes the cluster.

The examples assume an SSH alias `homelab` for the node (`~/.ssh/config`) and the kubeconfig at
`~/.kube/homelab.yaml`. Substitute your own names.

## 1. kubectl

k3s writes its kubeconfig to `/etc/rancher/k3s/k3s.yaml`, readable by root only. Its `server:` is
`https://127.0.0.1:6443`, a loopback address that the API certificate always covers. So you tunnel
port 6443 and leave the file's server address alone.

### One-time setup

Copy the kubeconfig to your workstation. Run the first block on the node and the second on your
workstation (a pipe through `ssh -t` mangles line endings and prompts, so use a temporary file):

```bash
# on the node
sudo cp /etc/rancher/k3s/k3s.yaml ~/k3s.yaml && sudo chown "$USER" ~/k3s.yaml
```

```bash
# on your workstation
mkdir -p ~/.kube
scp homelab:k3s.yaml ~/.kube/homelab.yaml
ssh homelab 'rm ~/k3s.yaml'
sed -i.bak 's/default/homelab/g' ~/.kube/homelab.yaml && rm ~/.kube/homelab.yaml.bak
chmod 600 ~/.kube/homelab.yaml
```

The `sed` renames the cluster, user and context from `default` to `homelab` so the file can sit
beside other kubeconfigs without a collision. The file contains the cluster's admin credentials:
keep it out of the repository (`.gitignore` already excludes kubeconfigs) and out of synced folders.

### Every session

```bash
ssh -N -L 6443:127.0.0.1:6443 homelab        # terminal 1: leave it running
```

```bash
export KUBECONFIG=~/.kube/homelab.yaml       # terminal 2
kubectl config current-context               # homelab
kubectl get nodes                            # Ready
```

`-L 6443:127.0.0.1:6443` makes your workstation listen on port 6443 and forward it through SSH to
port 6443 on the node. The address after the first port is resolved on the node. Add `-f` to run
the tunnel in the background; stop it with `pkill -f 'ssh -fN -L 6443'`.

`bootstrap/install.sh`, `scripts/infra-status.sh` and the other scripts use whatever `kubectl`
points at, so the tunnel and `KUBECONFIG` are all they need. Check `kubectl config current-context`
before running `bootstrap/install.sh`.

### Troubleshooting

| Symptom | Cause |
|---------|-------|
| `connection refused` on 6443 | the tunnel is not running, or died. Restart it |
| port 6443 already in use | another cluster (k3d, for example) holds it. Use `-L 6444:127.0.0.1:6443` and set `server: https://127.0.0.1:6444` in the kubeconfig |
| `no server found for cluster "minikube"` | `kubectl` is an alias for `minikube kubectl --`, which ignores `KUBECONFIG`. Run `unalias kubectl` or call the real binary (`which -a kubectl`) |
| a prompt that ends in the node's hostname | you are still inside an SSH session. `exit`, then run the command on your workstation |
| `x509` certificate error | you changed `server:` to a name the API certificate does not cover. Keep `127.0.0.1` and use the tunnel |

## 2. Reaching services: `kubectl port-forward`

With `kubectl` working, every service below is one `kubectl port-forward` away. The command runs
on your workstation, rides the same tunnel, and listens on `localhost`. Leave it running in its own
terminal and press Ctrl-C to stop. The local ports (18200, 8080, 15432, 16379) are arbitrary; pick
any free ones.

| Service | Namespace | Service name | Port |
|---------|-----------|--------------|------|
| Vault (API and UI) | `vault` | `vault` | 8200 |
| Argo CD (API and UI) | `argocd` | `argocd-server` | 443 |
| PostgreSQL (read-write) | `postgres` | `postgres-rw` | 5432 |
| Redis | `redis` | `redis` | 6379 |

## 3. Vault UI

```bash
kubectl -n vault port-forward svc/vault 18200:8200
```

Open <http://localhost:18200/ui/>. Sign in with method **Token** and the `root_token` from your
keys file (`~/.hl-helm/vault-init.json`, see [Rebuilding the cluster](bootstrap.md)). To copy it
without displaying it:

```bash
jq -r .root_token ~/.hl-helm/vault-init.json | pbcopy     # macOS; use xclip or wl-copy elsewhere
```

Secrets live in the `kv` engine (version 2): application credentials under `apps/<name>/…`,
infrastructure under `infra/…`. After a node restart the UI shows **Vault is sealed**; unseal it
with `bootstrap/vault-init.sh` (see [Rebuilding the cluster](bootstrap.md#after-a-node-restart)).

For the command line, `kubectl -n vault exec -it vault-0 -- env VAULT_ADDR=http://127.0.0.1:8200
VAULT_TOKEN=<token> vault kv get -mount=kv apps/<name>/postgres` works without a local `vault`
binary. Prefer the UI, or a token read from the file, over typing the root token into a shell where
it lands in history.

The root token is for setup and recovery. Do not hand it to applications: they authenticate through
the Kubernetes auth method and the per-chart policies that Vault Secrets Operator uses.

## 4. Argo CD UI

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Open <https://localhost:8080>. The browser warns about the certificate (it is self-signed); accept
it. Sign in as `admin`. Read the initial password with:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

Argo CD manages only the application tier (`charts/apps/*`), so you will see one Application per
application. The bootstrap and infrastructure tiers are not in it, by design
([tiers](tiers.md)). With the CLI instead of the UI:
`argocd login localhost:8080 --username admin --insecure`, then `argocd app list`.

The initial password secret is not rotated automatically. After changing the admin password you
may delete it: `kubectl -n argocd delete secret argocd-initial-admin-secret`.

## 5. PostgreSQL

```bash
kubectl -n postgres port-forward svc/postgres-rw 15432:5432
```

Each application gets its own database and role. Their passwords are in Vault, and VSO copies them
into a Secret named `postgres-<app>-credentials`. For the reference application:

```bash
PGPASSWORD=$(kubectl -n postgres get secret postgres-nginx-credentials -o jsonpath='{.data.password}' | base64 -d) \
  psql -h localhost -p 15432 -U nginx -d nginx
```

For administration, the cluster's owner role is `app`, with its generated password in the Secret
`postgres-app` (it also holds ready-made `uri`, `jdbc-uri` and `pgpass` keys):

```bash
PGPASSWORD=$(kubectl -n postgres get secret postgres-app -o jsonpath='{.data.password}' | base64 -d) \
  psql -h localhost -p 15432 -U app -d app
```

To run a one-off query without a port-forward or a local `psql`, use the pod:
`kubectl -n postgres exec -it postgres-1 -c postgres -- psql -U postgres`.

Inside the cluster an application connects to `postgres-rw.postgres.svc:5432` (read-write) or
`postgres-ro.postgres.svc:5432` (replicas).

## 6. Redis

```bash
kubectl -n redis port-forward svc/redis 16379:6379
```

Redis requires a password, held in Vault at `kv/infra/redis` and synced into the Secret
`redis-auth` in the `redis` namespace:

```bash
REDISCLI_AUTH=$(kubectl -n redis get secret redis-auth -o jsonpath='{.data.password}' | base64 -d) \
  redis-cli -p 16379 ping            # PONG
```

`REDISCLI_AUTH` keeps the password out of the process list and shell history. Without a local
`redis-cli`:

```bash
kubectl -n redis exec -it deploy/redis -- env REDISCLI_AUTH="$(kubectl -n redis get secret redis-auth -o jsonpath='{.data.password}' | base64 -d)" redis-cli
```

Inside the cluster applications use `redis.redis.svc:6379`.

## 7. The reference application over HTTPS

nginx is exposed through Traefik on the node's address, on ports 80 and 443, so it needs no
tunnel. Its hostname is a placeholder (`charts/apps/nginx/values.yaml`), so make your workstation
resolve it, either with `/etc/hosts` or per request:

```bash
echo "<node-ip> nginx.home.example" | sudo tee -a /etc/hosts
curl -k https://nginx.home.example/
# or, without editing /etc/hosts
curl -k --resolve nginx.home.example:443:<node-ip> https://nginx.home.example/
```

`-k` is needed because Traefik serves its built-in self-signed certificate until an issuer is
installed (`specs/001-extensible-helm-charts/research.md`, R-008). Plain HTTP on port 80 returns
404 rather than redirecting.

## Security notes

- The tunnel and the port-forwards listen on `localhost` only. Do not bind them to `0.0.0.0` (the
  `-L` and `port-forward --address` options) on a shared network.
- Secrets in these commands are read at the moment of use and never written into the repository.
  Keep it that way: no kubeconfig, token or password goes into a chart, a values file or a doc.
- The kubeconfig and the Vault keys file are the two credentials that grant full control. Keep
  `~/.kube/homelab.yaml` and `~/.hl-helm/vault-init.json` mode 600, and the keys file in a
  password manager as well.
