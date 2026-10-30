#!/usr/bin/env bash
# Run the helm-unittest suites that live inside individual charts (charts/<tier>/<name>/tests/).
# The hl-common suites under tests/unit are run separately by validate.sh.
#   scripts/chart-tests.sh            every chart that has a tests/ directory
#   scripts/chart-tests.sh <chart>... only these chart directories
set -uo pipefail
cd "${HL_ROOT:-$(dirname "$0")/..}"

if [ $# -gt 0 ]; then dirs=("$@"); else dirs=(charts/*/*/); fi
fail=0; ran=0
for d in "${dirs[@]}"; do
  d=${d%/}
  [ -d "$d/tests" ] || continue
  helm dependency build "$d" >/dev/null 2>&1 || helm dependency update "$d" >/dev/null
  ran=$((ran+1))
  if helm unittest -f 'tests/*_test.yaml' "$d"; then echo "chart tests ok: $d"; else echo "chart tests FAILED: $d"; fail=1; fi
done
[ $ran -eq 0 ] && echo "chart tests: none found"
exit $fail
