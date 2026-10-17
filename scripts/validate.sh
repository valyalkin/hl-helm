#!/usr/bin/env bash
# Pre-merge gate (FR-016): lint -> template -> helm unittest -> kubeconform -> policy -> docs.
#   scripts/validate.sh              run the full gate
#   scripts/validate.sh --self-test  inject six deliberate violations and assert each is caught
set -euo pipefail
cd "$(dirname "$0")/.."

[ "${1:-}" = "--self-test" ] && exec scripts/self-test.sh

K8S_VERSION="${K8S_VERSION:-1.31.0}"
CRD_CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
fail=0

echo "== lint / template / schema"
for chart in charts/*/*/Chart.yaml; do
  dir=$(dirname "$chart")
  tier=$(basename "$(dirname "$dir")")
  if [ "$tier" = library ]; then
    helm lint "$dir" >/dev/null && echo "lint ok: $dir" || { echo "lint FAILED: $dir"; fail=1; }
    continue
  fi
  helm dependency build "$dir" >/dev/null 2>&1 || helm dependency update "$dir" >/dev/null
  helm lint "$dir" >/dev/null || { echo "lint FAILED: $dir"; fail=1; }
  fixtures=("$dir"/ci/*.yaml)
  [ -e "${fixtures[0]}" ] || fixtures=("")
  for f in "${fixtures[@]}"; do
    args=(); [ -n "$f" ] && args=(-f "$f")
    if helm template ci "$dir" ${args[@]+"${args[@]}"} \
        | kubeconform -strict -ignore-missing-schemas -kubernetes-version "$K8S_VERSION" \
            -schema-location default -schema-location "$CRD_CATALOG" -summary >/dev/null; then
      echo "render+schema ok: $dir ${f}"
    else
      echo "render/schema FAILED: $dir ${f}"; fail=1
    fi
  done
done

echo "== unit tests"
helm dependency update tests/unit >/dev/null
helm unittest -f '*_test.yaml' tests/unit || fail=1

echo "== policy"
for check in tests/policy/*.py; do
  case "$(basename "$check")" in common.py) continue ;; esac
  python3 "$check" && echo "policy ok: $(basename "$check")" || { echo "policy FAILED: $(basename "$check")"; fail=1; }
done

echo "== docs"
if find charts -name 'README.md.gotmpl' | grep -q .; then
  helm-docs >/dev/null
  git diff --exit-code -- 'charts/**/README.md' >/dev/null || { echo "docs FAILED: helm-docs output is stale; run helm-docs and commit"; fail=1; }
else
  echo "docs skipped: no README.md.gotmpl templates yet"
fi

[ $fail -eq 0 ] && echo "GATE PASS" || echo "GATE FAIL"
exit $fail
