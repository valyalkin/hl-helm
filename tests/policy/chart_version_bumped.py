#!/usr/bin/env python3
"""Policy 5 (FR-018, Principle VI): a chart whose templates, values or dependencies changed
relative to the base ref must carry an advanced `version`.

Usage: chart_version_bumped.py [--base REF]   (default: origin/main, falling back to main)"""
import argparse
import subprocess
import yaml
from common import ROOT, charts, rel, finish

ap = argparse.ArgumentParser()
ap.add_argument("--base")
args = ap.parse_args()


def git(*a):
    return subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True, text=True)


base = args.base
for cand in ([base] if base else ["origin/main", "main"]):
    if git("rev-parse", "--verify", "-q", cand).returncode == 0:
        base = cand
        break
else:
    print("SKIP no base ref available")
    raise SystemExit(0)

merge_base = git("merge-base", base, "HEAD").stdout.strip() or base
WATCHED = ("templates/", "values.yaml", "values.schema.json", "Chart.yaml", "files/")


def semver(v):
    return tuple(int(x) for x in str(v).split("+")[0].split("-")[0].split("."))


failures = []
for tier, d in charts():
    r = rel(d)
    changed = git("diff", "--name-only", merge_base, "--", r).stdout.split()
    untracked = git("ls-files", "--others", "--exclude-standard", "--", r).stdout.split()
    changed = [c for c in changed + untracked if c[len(r) + 1:].startswith(WATCHED)]
    if not changed:
        continue
    old = git("show", f"{merge_base}:{r}/Chart.yaml")
    if old.returncode:  # new chart
        continue
    old_v = yaml.safe_load(old.stdout)["version"]
    new_v = yaml.safe_load((d / "Chart.yaml").read_text())["version"]
    if semver(new_v) <= semver(old_v):
        failures.append(f"{r}/Chart.yaml: version {new_v} not advanced past {old_v} "
                        f"although {changed[0]} changed")
finish(failures)
