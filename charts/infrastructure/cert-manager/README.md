# cert-manager

cert-manager operator wrapper chart (feature 005, home and remote access). It issues and renews
the homelab's one shared certificate for `<domain>` and `*.<domain>`. The `Issuer`, the
`Certificate` and Traefik's default TLS store are the separate `ingress-tls` chart, installed
after this one, because a release cannot create the cert-manager CRDs and use them in the same
install.

CRDs are installed by this chart (`crds.enabled`) and kept on uninstall (`crds.keep`, upstream
default), so removing the release never deletes issued certificates.

## Storage, backup and restore

Stateless. Certificates live in Kubernetes Secrets in the `ingress-tls` namespace and are simply
reissued if lost (Let's Encrypt, DNS-01).

## Deviation from the constitution

Principle VII prefers k3s built-ins over operators. This chart adds an operator instead of
Traefik's built-in ACME resolver because the built-in resolver keeps the certificate inside the
k3s-managed Traefik release (a file in its volume, with the DNS token in `kube-system`): it
cannot be inspected as a resource, reused outside Traefik, or reported by
`scripts/infra-status.sh`. cert-manager exposes the certificate as a `Certificate` with a `Ready`
condition and expiry date (hl-budget-spec feature 005, plan.md Complexity Tracking).

Expiry condition: revisit if Traefik-native certificates become inspectable and shareable as
Kubernetes resources.

Pins upstream chart `cert-manager` v1.21.3.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cert-manager.cainjector.resources | object | `{"limits":{"memory":"128Mi"},"requests":{"cpu":"10m","memory":"64Mi"}}` | CA injector resources. |
| cert-manager.crds | object | `{"enabled":true}` | Install and upgrade the CRDs with the chart. `crds.keep` (upstream default true) leaves them in place on uninstall, so certificates survive a reinstall. |
| cert-manager.dns01RecursiveNameservers | string | `"1.1.1.1:53,8.8.8.8:53"` | DNS-01 self-check asks public resolvers only, not the cluster DNS, so a freshly written `_acme-challenge` record is seen as Let's Encrypt sees it. |
| cert-manager.dns01RecursiveNameserversOnly | bool | `true` | See `dns01RecursiveNameservers`. |
| cert-manager.resources | object | `{"limits":{"memory":"128Mi"},"requests":{"cpu":"10m","memory":"64Mi"}}` | Controller resources (the node is shared; every container needs a memory limit). |
| cert-manager.startupapicheck.resources | object | `{"limits":{"memory":"64Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}` | Post-install API check job resources. |
| cert-manager.webhook.resources | object | `{"limits":{"memory":"64Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}` | Webhook resources. |
