#!/usr/bin/env bash
# The single manual command (FR-058): install the bootstrap and infrastructure tiers in
# dependency order, then Argo CD, then the ApplicationSet that deploys charts/apps/*.
#
#   bootstrap/install.sh [options]
#     --context CTX            kubectl/helm context (default: current)
#     --keys-file PATH         where Vault's unseal key and root token live, OUTSIDE the repo
#                              (default ~/.hl-helm/vault-init.json)
#     --repo-url URL           Git URL Argo CD should read (default: the URL in the ApplicationSet)
#     --repo-credential VALUE  optional: a file holding a token or an SSH private key. Written
#                              only into the Argo CD repository Secret — never committed, never
#                              read from Vault (FR-033, research R-007)
#     --only NAME              install/upgrade just one release from install-order.yaml
#     --diff                   preview with `helm diff upgrade` instead of applying (needs the
#                              helm-diff plugin); this is the review gate for these tiers
set -euo pipefail
cd "$(dirname "$0")/.."

CTX_ARGS=(); HELM_CTX=(); KEYS_FILE="${HOME}/.hl-helm/vault-init.json"
REPO_URL=""; REPO_CRED=""; ONLY=""; DIFF=0
while [ $# -gt 0 ]; do
  case "$1" in
    --context)         CTX_ARGS=(--context "$2"); HELM_CTX=(--kube-context "$2"); shift 2 ;;
    --keys-file)       KEYS_FILE=$2; shift 2 ;;
    --repo-url)        REPO_URL=$2; shift 2 ;;
    --repo-credential) REPO_CRED=$2; shift 2 ;;
    --only)            ONLY=$2; shift 2 ;;
    --diff)            DIFF=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

for t in helm kubectl jq; do command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }; done
H() { helm "${HELM_CTX[@]+"${HELM_CTX[@]}"}" "$@"; }
K() { kubectl "${CTX_ARGS[@]+"${CTX_ARGS[@]}"}" "$@"; }

# Upgrades are applied from a committed state only (constitution, Development Workflow).
if [ "$DIFF" -eq 0 ] && [ -n "$(git status --porcelain -- charts bootstrap argocd 2>/dev/null)" ]; then
  echo "refusing to apply from an uncommitted working tree; commit first, or use --diff" >&2
  exit 1
fi

# Minimal reader for the flat install-order.yaml: emits "name|chart|namespace|values|after".
entries() {
  awk '
    function flush() { if (name != "") print name "|" chart "|" ns "|" vals "|" after; name=chart=ns=vals=after="" }
    /^install:/ { in_install=1; next }
    /^[a-z]/    { if (in_install) flush(); in_install=0 }
    in_install && /^  - name:/ { flush(); name=$3; next }
    in_install && /^    chart:/     { chart=$2 }
    in_install && /^    namespace:/ { ns=$2 }
    in_install && /^    values:/    { vals=$2 }
    in_install && /^    after:/     { after=$2 }
    END { if (in_install) flush() }
  ' bootstrap/install-order.yaml
}
argo() { awk -v k="$1" '/^argocd:/ {a=1; next} /^[a-z]/ {a=0} a && $1==k":" {print $2}' bootstrap/install-order.yaml; }

deploy() { # name chart namespace values
  local name=$1 chart=$2 ns=$3 vals=$4 args=()
  [ -n "$vals" ] && args=(-f "$vals")
  H dependency build "$chart" >/dev/null 2>&1 || H dependency update "$chart" >/dev/null
  if [ "$DIFF" -eq 1 ]; then
    H diff upgrade "$name" "$chart" -n "$ns" ${args[@]+"${args[@]}"} || true
  else
    echo "==> $name ($chart -> $ns)"
    H upgrade --install "$name" "$chart" -n "$ns" --create-namespace ${args[@]+"${args[@]}"} --wait --timeout 10m
  fi
}

while IFS='|' read -u 3 -r name chart ns vals after; do
  [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && continue
  deploy "$name" "$chart" "$ns" "$vals"
  if [ "$DIFF" -eq 0 ] && [ "$after" = vault-init ]; then
    bootstrap/vault-init.sh --keys-file "$KEYS_FILE" ${CTX_ARGS[@]+"${CTX_ARGS[@]}"}
  fi
done 3< <(entries)

if [ -z "$ONLY" ] || [ "$ONLY" = "$(argo name)" ]; then
  AS=$(argo applicationset)
  deploy "$(argo name)" "$(argo chart)" "$(argo namespace)" "$(argo values)"
  if [ "$DIFF" -eq 0 ]; then
    if [ -n "$REPO_CRED" ] || [ -n "$REPO_URL" ]; then
      url=${REPO_URL:-$(awk '/repoURL:/ {print $2; exit}' "$AS")}
    fi
    if [ -n "$REPO_CRED" ]; then
      [ -f "$REPO_CRED" ] || { echo "--repo-credential must be a file" >&2; exit 1; }
      if grep -q 'BEGIN .*PRIVATE KEY' "$REPO_CRED"; then field=sshPrivateKey; else field=password; fi
      K -n argocd create secret generic hl-helm-repo --dry-run=client -o yaml \
        --from-literal=type=git --from-literal=url="$url" \
        ${field:+--from-file="$field=$REPO_CRED"} \
        $([ "$field" = password ] && echo --from-literal=username=git) \
        | K label --local -f - argocd.argoproj.io/secret-type=repository -o yaml | K apply -f -
    fi
    echo "==> ApplicationSet ($AS)"
    if [ -n "$REPO_URL" ]; then
      sed "s#https://github.com/valyalkin/hl-helm.git#${REPO_URL}#g" "$AS" | K apply -f -
    else
      K apply -f "$AS"
    fi
    echo "Done. Argo CD now reconciles charts/apps/*. Watch: kubectl -n argocd get applications"
  fi
fi
