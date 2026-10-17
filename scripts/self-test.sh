#!/usr/bin/env bash
# Inject six deliberate violations into a throwaway copy of the repository and assert that the
# gate rejects each one, naming the offending file and value (quickstart step 1).
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
rsync -a --exclude 'charts/**/charts/' --exclude '*.tgz' "$here/" "$work/" 
cd "$work" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm base --allow-empty
export HL_ROOT="$work"
helm dependency update charts/apps/nginx >/dev/null

pass=0; total=0
expect() { # name, needle-1, needle-2, command...
  local name=$1 n1=$2 n2=$3; shift 3
  total=$((total+1))
  out=$("$@" 2>&1); rc=$?
  if [ $rc -ne 0 ] && grep -qF -- "$n1" <<<"$out" && grep -qF -- "$n2" <<<"$out"; then
    echo "caught   $name  ($n1 / $n2)"; pass=$((pass+1))
  else
    echo "MISSED   $name (rc=$rc, wanted '$n1' and '$n2')"; echo "$out" | sed 's/^/    /'
  fi
}
reset() { git checkout -q -- . && git clean -fdq -e charts/apps/nginx/charts -e tests/unit/charts; }

# 1. mutable image tag in a raw manifest (bypasses the library's own guard)
printf 'apiVersion: v1\nkind: Pod\nmetadata: {name: x}\nspec:\n  containers:\n    - name: x\n      image: busybox:latest\n' > charts/apps/nginx/templates/raw.yaml
expect "mutable image tag" "busybox:latest" "charts/apps/nginx" python3 tests/policy/no_mutable_tags.py
reset

# 2. embedded dependency in an application chart
cat >> charts/apps/nginx/Chart.yaml <<'Y'
  - name: redis
    version: "1.0.0"
    repository: "file://../../infrastructure/redis"
Y
expect "embedded dependency" "charts/apps/nginx/Chart.yaml" "redis" python3 tests/policy/no_embedded_dependencies.py
reset

# 3. secret material
printf 'db:\n  password: hunter2hunter2\n' > charts/apps/nginx/ci/leak.yaml
expect "secret material" "charts/apps/nginx/ci/leak.yaml" "literal credential" python3 tests/policy/no_secret_material.py
reset

# 4. bootstrap-tier chart with a secret reference
mkdir -p charts/bootstrap/selftest
printf 'apiVersion: v2\nname: selftest\nversion: 0.1.0\n' > charts/bootstrap/selftest/Chart.yaml
printf 'secrets:\n  db: {vaultPath: kv/db}\n' > charts/bootstrap/selftest/values.yaml
expect "bootstrap secret reference" "charts/bootstrap/selftest/values.yaml" "FR-056" python3 tests/policy/reference_and_tiers.py
reset

# 5. template changed without a version bump
echo '# changed' >> charts/apps/nginx/templates/web.yaml
expect "version not bumped" "charts/apps/nginx/Chart.yaml" "not advanced" python3 tests/policy/chart_version_bumped.py --base HEAD
reset

# 6. invalid value rejected at render time (memory limit removed)
sed -i.bak -e '/limits: {memory: 64Mi}/d' -e '/^    resources:$/d' charts/apps/nginx/values.yaml && rm charts/apps/nginx/values.yaml.bak
expect "missing memory limit" "web.workload.resources.limits.memory" "nginx" helm template ci charts/apps/nginx
reset

echo "$pass of $total violations caught"
[ $pass -eq $total ]
