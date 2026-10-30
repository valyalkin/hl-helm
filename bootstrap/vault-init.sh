#!/usr/bin/env bash
# Initialise (first run), unseal, and configure Vault for the cluster. Idempotent.
#
#   bootstrap/vault-init.sh [--keys-file PATH] [--context CTX] [--namespace NS]
#
# The unseal key and root token are written to --keys-file, OUTSIDE the repository
# (default ~/.hl-helm/vault-init.json, mode 600). Back that file up somewhere that is not this
# cluster: without it a restarted Vault cannot be unsealed (FR-059).
set -euo pipefail

KEYS_FILE="${HOME}/.hl-helm/vault-init.json"
NS=vault
CTX_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --keys-file) KEYS_FILE=$2; shift 2 ;;
    --context)   CTX_ARGS=(--context "$2"); shift 2 ;;
    --namespace) NS=$2; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$(cd "$(dirname "$KEYS_FILE")" 2>/dev/null && pwd)/" in
  "$(cd "$(dirname "$0")/.." && pwd)"/*) echo "refusing to write unseal material inside the repository" >&2; exit 1 ;;
esac

k()  { kubectl "${CTX_ARGS[@]+"${CTX_ARGS[@]}"}" -n "$NS" "$@"; }
vx() { k exec -i vault-0 -- env VAULT_ADDR=http://127.0.0.1:8200 "$@"; }
vt() { k exec -i vault-0 -- env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="$ROOT_TOKEN" "$@"; }

k wait --for=condition=Ready pod/vault-0 --timeout=300s >/dev/null 2>&1 || true
until vx vault status -format=json >/dev/null 2>&1 || [ $? -eq 2 ]; do sleep 2; done

status=$(vx vault status -format=json 2>/dev/null || true)
initialized=$(jq -r .initialized <<<"$status")

if [ "$initialized" != true ]; then
  mkdir -p "$(dirname "$KEYS_FILE")"; chmod 700 "$(dirname "$KEYS_FILE")"
  (umask 077; vx vault operator init -key-shares=1 -key-threshold=1 -format=json > "$KEYS_FILE")
  echo "initialised; unseal material saved to $KEYS_FILE — back it up outside the cluster"
fi
[ -f "$KEYS_FILE" ] || { echo "Vault is initialised but $KEYS_FILE is missing" >&2; exit 1; }

UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' "$KEYS_FILE")
ROOT_TOKEN=$(jq -r .root_token "$KEYS_FILE")

if [ "$(jq -r .sealed <<<"$(vx vault status -format=json 2>/dev/null || true)")" != false ]; then
  vx vault operator unseal "$UNSEAL_KEY" >/dev/null
  echo "unsealed"
fi

# --- configuration: KV, Kubernetes auth, policies, roles ------------------------------------
vt vault secrets list -format=json | jq -e '."kv/"' >/dev/null 2>&1 || vt vault secrets enable -path=kv -version=2 kv >/dev/null
vt vault auth list -format=json | jq -e '."kubernetes/"' >/dev/null 2>&1 || vt vault auth enable kubernetes >/dev/null
vt sh -c 'vault write auth/kubernetes/config kubernetes_host="https://$KUBERNETES_SERVICE_HOST:443"' >/dev/null

ACCESSOR=$(vt vault auth list -format=json | jq -r '."kubernetes/".accessor')

# Applications read only kv/apps/<their own namespace>/*; the policy is templated on the
# caller's namespace, so onboarding an application needs no Vault change.
vt vault policy write apps - >/dev/null <<POLICY
path "kv/data/apps/{{identity.entity.aliases.${ACCESSOR}.metadata.service_account_namespace}}/*" {
  capabilities = ["read"]
}
path "kv/data/infra/redis" {
  capabilities = ["read"]
}
POLICY
vt vault policy write infra-read - >/dev/null <<'POLICY'
path "kv/data/apps/+/postgres" { capabilities = ["read"] }
path "kv/data/infra/*"         { capabilities = ["read"] }
POLICY
# The shared ingress certificate and the Tailscale gateway each read only their own credential
# (owner-written: kv/infra/cloudflare api_token, kv/infra/tailscale client_secret).
vt vault policy write edge - >/dev/null <<'POLICY'
path "kv/data/infra/cloudflare" { capabilities = ["read"] }
path "kv/data/infra/tailscale"  { capabilities = ["read"] }
POLICY
vt vault policy write provision - >/dev/null <<'POLICY'
path "kv/data/apps/+/postgres" { capabilities = ["create", "read"] }
path "kv/data/infra/*"         { capabilities = ["create", "read"] }
POLICY

vt vault write auth/kubernetes/role/apps \
  bound_service_account_names='*' bound_service_account_namespaces='*' \
  audience=vault token_policies=apps ttl=1h >/dev/null
vt vault write auth/kubernetes/role/infra \
  bound_service_account_names=postgres-vault,redis bound_service_account_namespaces=postgres,redis \
  audience=vault token_policies=infra-read ttl=1h >/dev/null
vt vault write auth/kubernetes/role/provision \
  bound_service_account_names=provisioner bound_service_account_namespaces=postgres,redis \
  token_policies=provision ttl=10m >/dev/null
vt vault write auth/kubernetes/role/edge \
  bound_service_account_names=ingress-tls,tailscale bound_service_account_namespaces=ingress-tls,tailscale \
  audience=vault token_policies=edge ttl=1h >/dev/null
echo "vault configured: kv/, kubernetes auth, roles apps / infra / provision / edge"
