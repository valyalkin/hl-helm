# ingress-tls

The homelab's shared trusted certificate and Traefik's HTTPS defaults (hl-budget-spec feature
005, home and remote access). Installed by `bootstrap/install.sh` after `cert-manager`.

| Object | What it does |
|---|---|
| `VaultStaticSecret` `cloudflare-api-token` | Syncs the Cloudflare API token from Vault `kv/infra/cloudflare` (key `api_token`) through VSO, role `edge` |
| `Issuer` `letsencrypt` | Let's Encrypt ACME account; DNS-01 challenges answered through the Cloudflare API, so nothing needs to be reachable from the internet |
| `Certificate` `wildcard` | One certificate for `<domain>` and `*.<domain>`, stored in Secret `wildcard-tls`, renewed automatically at two thirds of its lifetime |
| `TLSStore` `default` | Makes `wildcard-tls` Traefik's default certificate, so every Ingress without its own `tls.secretName` (the hl-common default) is served with it |
| `HelmChartConfig` `traefik` (`kube-system`) | Configures the k3s-bundled Traefik to redirect every HTTP request to HTTPS. This chart owns the cluster's only Traefik HelmChartConfig |

## Operating it

- **First install / rebuild**: install with `acme.server: staging`, wait for
  `kubectl -n ingress-tls get certificate wildcard` to show `READY True`, then switch
  `bootstrap/values/ingress-tls.yaml` to `production` and apply again. Staging avoids Let's
  Encrypt rate limits while something is wrong.
- **Health**: `scripts/infra-status.sh` prints the certificate's readiness and expiry. A failed
  renewal shows `READY False` with cert-manager's reason, while the previous certificate keeps
  serving until it expires.
- **Rotating the Cloudflare token**: create a new token (Zone → DNS → Edit, this zone only),
  write it to `kv/infra/cloudflare`, revoke the old one. VSO picks it up within `refreshAfter`.
- **Forcing a renewal**: `cmctl renew -n ingress-tls wildcard`, or delete Secret `wildcard-tls`.

## Storage, backup and restore

No persistent data. The certificate Secret and the ACME account key are recreated by cert-manager
if lost; the only input that must be kept is the Cloudflare token in Vault.

## Deviation from the constitution

None. The `HelmChartConfig` is a k3s built-in mechanism for configuring the bundled Traefik
(Principle VII).

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| acme.email | string | `""` | OPTIONAL: ACME account contact email. Left empty on purpose: Let's Encrypt no longer sends expiry emails, and this repository is public. Renewal health is reported by scripts/infra-status.sh instead |
| acme.server | string | `"staging"` | `staging` (safe default, untrusted certificates, generous rate limits) or `production` |
| cloudflare.refreshAfter | string | `"1h"` | How often VSO re-reads the token, so a rotated token is picked up without a restart |
| cloudflare.vaultPath | string | `"infra/cloudflare"` | Vault KV path of the Cloudflare API token (key `api_token`, permission Zone → DNS → Edit on this domain only). Written by the owner; this chart carries the path only |
| domain | string | `""` | REQUIRED: the homelab domain, without scheme or wildcard. The certificate covers it and every first-level name under it. Set in bootstrap/values/ingress-tls.yaml. Example: `example.com` |
| redirectHttpToHttps | bool | `true` | Render the k3s `HelmChartConfig` that makes Traefik redirect every HTTP request to HTTPS. This chart owns the cluster's only Traefik HelmChartConfig |
| tlsStore.namespace | string | `""` | Namespace of the default TLSStore and the Certificate (they must share it, because the store names the certificate Secret). Empty means the release namespace; use `kube-system` only if Traefik ignores a default store elsewhere |
| vaultAuth | object | `{"createNamespace":false,"role":"edge"}` | Vault binding rendered by hl-common (ServiceAccount `ingress-tls` + VaultAuth, role `edge`). The namespace itself is created by `helm --create-namespace` |
