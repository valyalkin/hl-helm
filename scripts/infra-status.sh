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
K() { kubectl "${HC[@]+"${HC[@]/--kube-context/--context}"}" "$@"; }

# The shared certificate (feature 005). Fewer than 14 days left means renewal has failed for
# about two weeks: cert-manager renews at two thirds of the lifetime.
echo
echo "Certificates (ingress-tls):"
printf '%-12s %-7s %-22s %s\n' NAME READY NOT-AFTER DAYS-LEFT
K -n ingress-tls get certificates -o json 2>/dev/null | jq -r '
  .items[] |
  ([.status.conditions[]? | select(.type == "Ready")][0]) as $r |
  (.status.notAfter // "") as $na |
  (if $na == "" then "-" else ((($na | fromdateiso8601) - now) / 86400 | floor) end) as $days |
  [ .metadata.name, ($r.status // "Unknown"), (if $na == "" then "-" else $na end),
    (if ($days | type) == "number" and $days < 14 then "\($days) RENEWAL OVERDUE" else "\($days)" end),
    (if ($r.status // "") != "True" then "  " + ($r.message // "no Ready condition yet") else "" end) ] |
  "\(.[0])\t\(.[1])\t\(.[2])\t\(.[3])\(.[4])"' | awk -F'\t' '{printf "%-12s %-7s %-22s %s\n", $1, $2, $3, $4}' \
  || echo "  (none: is ingress-tls installed?)"

# The Tailscale gateway (feature 005): is it running, and what does tailscaled say about itself?
echo
echo "Tailscale gateway:"
ts=$(K -n tailscale get pod tailscale-0 -o jsonpath='{.status.phase} ready={.status.containerStatuses[0].ready}' 2>/dev/null) \
  && echo "  pod tailscale-0: $ts" || echo "  (not installed)"
if [ -n "${ts:-}" ]; then
  K -n tailscale exec tailscale-0 -- tailscale --socket=/tmp/tailscaled.sock status --json 2>/dev/null \
    | jq -r '"  \(.Self.HostName) online=\(.Self.Online) routes=\((.Self.PrimaryRoutes // []) | join(",")) state=\(.BackendState)"' \
    || echo "  status unavailable"
fi

echo
echo "Unhealthy pods in infrastructure namespaces:"
for ns in vault vault-secrets-operator cnpg-system postgres redis cert-manager ingress-tls tailscale argocd; do
  K -n "$ns" get pods --no-headers 2>/dev/null | grep -vE 'Running|Completed' || true
done
