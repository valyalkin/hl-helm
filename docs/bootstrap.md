# Rebuilding the cluster

The repository can rebuild the homelab from an empty k3s node with one command. This page is the
procedure, including the one step that needs a human: holding Vault's unseal material.

## Prerequisites

- A k3s node (Traefik and `local-path` enabled — the k3s defaults) and a kubeconfig for it (see [Accessing the cluster](access.md))
- On your workstation: `helm` 4.x, `kubectl`, `jq`; the `helm-diff` plugin for upgrades
- This repository checked out at a **committed** state (`install.sh` refuses a dirty tree)

## Rebuild

```sh
bootstrap/install.sh [--context <ctx>] [--keys-file <path>] [--repo-credential <file>]
```

In order, waiting for each to be healthy: Vault → Vault Secrets Operator → CloudNativePG →
Postgres → Redis → cert-manager → ingress-tls → Tailscale → Argo CD → the ApplicationSet. After
Vault installs, the script initialises, unseals and configures it (`bootstrap/vault-init.sh`):
the KV mount, Kubernetes auth, and the `apps`, `infra`, `provision` and `edge` roles.

**Owner-written credentials.** `ingress-tls` and `tailscale` wait for two values only the owner
can supply. On a cold rebuild Vault is empty, so write them right after Vault is initialised and
before those two releases install, or their install times out and has to be re-run with
`--only`:

```sh
vault kv put kv/infra/cloudflare api_token=-     # Cloudflare token: Zone · DNS · Edit, valyalkin.com only
vault kv put kv/infra/tailscale  client_secret=- # Tailscale OAuth client: Auth Keys: Write, tag:homelab
```

Both can be re-created in the Cloudflare and Tailscale consoles if lost. The app secrets under
`kv/apps/` can't: Vault has no backup yet, and a running cluster's VSO-synced Secrets are the only
other copy. From there Argo CD discovers every `charts/apps/*` chart
and deploys it. Nothing else is run by hand.

The repository is public, so Argo CD reads it anonymously. Pass `--repo-credential <file>` (a token
or an SSH private key) to avoid anonymous rate limits during a cold rebuild or when the repository
turns private. It is written only into the Argo CD repository Secret — never committed, never read
from Vault. `--repo-url` points Argo CD at a different Git URL (used for testing against a local
Git server).

Measured on a disposable k3d cluster: about 4 minutes from empty to all applications `Synced` and
`Healthy` (target: 2 hours, SC-005).

## Vault initialisation and unseal

`bootstrap/vault-init.sh` is idempotent and is run by `install.sh`:

- First run: `vault operator init` (1 key share, threshold 1), writes the unseal key and root token
  to `~/.hl-helm/vault-init.json` (mode 600). It refuses to write inside the repository.
- Every later run: unseals if sealed, then re-applies configuration.

**Store that file outside the cluster and outside this repository now** — a password manager, not
Git. Without it a restarted Vault cannot be unsealed and its data is unreadable (FR-059). A single
key share is a deliberate homelab trade-off: raise the share count in the script if more than one
person holds the key.

### After a node restart

Vault comes back **sealed**. Its probes accept that state, so the pod is reachable; run

```sh
bootstrap/vault-init.sh --keys-file <path>
```

Workloads that were already running keep working: their Kubernetes Secrets persist, and sealing
Vault stops only *new* syncs and rotations until it is unsealed.

## Certificates

One Let's Encrypt certificate, for `valyalkin.com` and `*.valyalkin.com`, is Traefik's default and
serves every app (`charts/infrastructure/ingress-tls`).

- **Renewal**: cert-manager renews at two thirds of the lifetime, about 30 days before expiry for
  a 90-day certificate. It proves ownership by writing a `_acme-challenge` TXT record through the
  Cloudflare API, so nothing has to be reachable from the internet.
- **Where to look**: `scripts/infra-status.sh` prints *Certificates* with `READY`, the expiry date
  and days left, flagged `RENEWAL OVERDUE` under 14 days. Detail:
  `kubectl -n ingress-tls describe certificate wildcard` and its CertificateRequest, Order and
  Challenge. A failed renewal leaves the old certificate serving until it expires.
- **Rotating the Cloudflare token**: create a new token (Zone · DNS · Edit, this zone only), write
  it to `kv/infra/cloudflare`, then revoke the old one. VSO picks it up within an hour.
- **Forcing a renewal**: `cmctl renew -n ingress-tls wildcard`. Deleting Secret `wildcard-tls`
  also works, but Traefik falls back to its self-signed certificate for the 2–3 minutes until the
  new one is issued.
- **Rebuilding from scratch**: install `ingress-tls` with `acme.server: staging`, wait for
  `READY True`, then switch `bootstrap/values/ingress-tls.yaml` to `production` and apply again
  (chart README). Let's Encrypt allows 5 identical certificates per week, so debug on staging.

## Upgrading an infrastructure or bootstrap chart

A merge to `main` never changes these tiers — only Argo CD applies on merge, and it manages
`charts/apps/` only. To upgrade:

```sh
bootstrap/install.sh --only postgres --diff      # helm diff upgrade: review this
git status                                       # must be clean — apply from a committed state
bootstrap/install.sh --only postgres             # helm upgrade --install
```

Paste the diff into the change description (Principle III). To report whether the live cluster
still matches the repository, see `docs/tiers.md`.

## Exercise the rebuild regularly

Nothing watches the infrastructure tiers for out-of-band change, so a rebuild on a disposable
cluster is the only proof the repository still matches reality (constitution, Development
Workflow):

```sh
k3d cluster create homelab-test --servers 1
bootstrap/install.sh --context k3d-homelab-test --keys-file /tmp/test-vault-keys.json
```

See also [`docs/tiers.md`](tiers.md), [`docs/onboarding.md`](onboarding.md) and the repository [`README.md`](../README.md).
