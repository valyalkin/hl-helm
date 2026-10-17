"""Shared helpers for repository policy checks. Run from any directory; ROOT is the repo root
(overridable with HL_ROOT so --self-test can point checks at a mutated copy)."""
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(os.environ.get("HL_ROOT") or pathlib.Path(__file__).resolve().parents[2])
TIERS = ("library", "bootstrap", "infrastructure", "apps")


def charts(tiers=TIERS):
    """Yield (tier, chart_dir) for every chart under charts/<tier>/<name>/."""
    for tier in tiers:
        base = ROOT / "charts" / tier
        if base.is_dir():
            for d in sorted(base.iterdir()):
                if (d / "Chart.yaml").is_file():
                    yield tier, d


def rel(p):
    return str(pathlib.Path(p).relative_to(ROOT))


def render(chart_dir, values_file=None):
    """helm template a chart (dependencies must already be built). Returns stdout or exits."""
    cmd = ["helm", "template", "policy", str(chart_dir)]
    if values_file:
        cmd += ["-f", str(values_file)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        print(f"FAIL {rel(chart_dir)}: helm template failed: {r.stderr.strip().splitlines()[-1]}")
        sys.exit(1)
    return r.stdout


def fixtures(chart_dir):
    found = sorted((chart_dir / "ci").glob("*.yaml"))
    return found or [None]


def tracked_files():
    out = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-co", "--exclude-standard"],
                         capture_output=True, text=True, check=True).stdout.split("\n")
    return [ROOT / f for f in out if f and (ROOT / f).is_file()]


def finish(failures):
    for f in failures:
        print(f"FAIL {f}")
    sys.exit(1 if failures else 0)
