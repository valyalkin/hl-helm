#!/usr/bin/env bash
# Report the state of the bootstrap and infrastructure tiers (FR-034, SC-017). Argo CD does not
# watch these, so this is the only drift report there is.
#   scripts/infra-status.sh [--context CTX]
# For each release in bootstrap/install-order.yaml: deployed chart version vs the repository's,
# the release status, and — when the helm-diff plugin is installed — whether the live release
# differs from what the repository would apply.
set -euo pipefail
cd "$(dirname "$0")/.."
HC=(); [ "${1:-}" = "--context" ] && HC=(--kube-context "$2")
H() { helm "${HC[@]+"${HC[@]}"}" "$@"; }

printf '%-24s %-10s %-10s %-10s %s\n' RELEASE DEPLOYED REPO STATUS DRIFT
while IFS='|' read -r name chart ns vals; do
  repo_v=$(awk '/^version:/ {print $2}' "$chart/Chart.yaml")
  live=$(H list -n "$ns" -f "^${name}\$" -o json 2>/dev/null)
  dep_v=$(jq -r '.[0].chart // "-"' <<<"$live" | sed "s/^${name}-//")
  status=$(jq -r '.[0].status // "MISSING"' <<<"$live")
  drift="n/a"
  if H plugin list 2>/dev/null | grep -q '^diff'; then
    args=(); [ -n "$vals" ] && args=(-f "$vals")
    if H diff upgrade "$name" "$chart" -n "$ns" ${args[@]+"${args[@]}"} --three-way-merge --no-hooks --detailed-exitcode >/dev/null 2>&1; then drift=none; else drift=DRIFT; fi
  fi
  printf '%-24s %-10s %-10s %-10s %s\n' "$name" "$dep_v" "$repo_v" "$status" "$drift"
done < <(awk '
  function flush() { if (name != "") print name "|" chart "|" ns "|" vals; name=chart=ns=vals="" }
  /^install:/ { i=1; next } /^[a-z]/ { if (i) flush(); i=0 }
  i && /^  - name:/ { flush(); name=$3; next }
  i && /^    chart:/ {chart=$2} i && /^    namespace:/ {ns=$2} i && /^    values:/ {vals=$2}
  END { if (i) flush() }' bootstrap/install-order.yaml)
echo
echo "Unhealthy pods in infrastructure namespaces:"
for ns in vault vault-secrets-operator cnpg-system postgres redis argocd; do
  kubectl "${HC[@]+"${HC[@]/--kube-context/--context}"}" -n "$ns" get pods --no-headers 2>/dev/null | grep -vE 'Running|Completed' || true
done
