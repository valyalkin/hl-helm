#!/usr/bin/env bash
# Development gate: lint, template (every ci/ fixture), helm unittest, kubeconform.
# Expanded to the full gate (policy checks, helm-docs) in US5.
set -euo pipefail
cd "$(dirname "$0")/.."

K8S_VERSION="${K8S_VERSION:-1.31.0}"
fail=0

for chart in charts/*/*/Chart.yaml; do
  dir=$(dirname "$chart")
  tier=$(basename "$(dirname "$dir")")
  if [ "$tier" = library ]; then
    helm lint "$dir" >/dev/null || fail=1
    echo "lint ok: $dir"
    continue
  fi
  helm dependency update "$dir" >/dev/null
  helm lint "$dir" >/dev/null || { echo "lint FAILED: $dir"; fail=1; }
  fixtures=("$dir"/ci/*.yaml)
  [ -e "${fixtures[0]}" ] || fixtures=("")
  for f in "${fixtures[@]}"; do
    args=(); [ -n "$f" ] && args=(-f "$f")
    if helm template ci "$dir" ${args[@]+"${args[@]}"} \
        | kubeconform -strict -ignore-missing-schemas -kubernetes-version "$K8S_VERSION" -summary >/dev/null; then
      echo "render+schema ok: $dir ${f}"
    else
      echo "render/schema FAILED: $dir ${f}"; fail=1
    fi
  done
done

helm dependency update tests/unit >/dev/null
helm unittest -f '*_test.yaml' tests/unit || fail=1

exit $fail
