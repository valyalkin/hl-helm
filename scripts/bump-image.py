#!/usr/bin/env python3
"""Pin a new image for one service of one application, and bump the chart's patch version.

    scripts/bump-image.py <app> <service> <tag> <digest>
    scripts/bump-image.py todo api 42-3f9c2ab sha256:...

Called by a service repository's release workflow after it pushes an image (docs/onboarding.md,
"Releasing from a service repository"). Edits charts/apps/<app>/values.yaml in place, keeping
comments: sets <service>.workload.image.tag and .digest (block style is required). Then bumps
`version` in charts/apps/<app>/Chart.yaml, as the chart_version_bumped policy demands.
Regenerates that chart's README with helm-docs (the docs gate fails otherwise).
Prints the new chart version. Exits non-zero, naming the problem, when the app or the service
block does not exist: onboarding a service is a reviewed chart change, not a bump.
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent


def die(msg):
    print(f"bump-image: {msg}", file=sys.stderr)
    raise SystemExit(1)


def indent(line):
    return len(line) - len(line.lstrip(" "))


def meaningful(line):
    s = line.strip()
    return s and not s.startswith("#")


def child(lines, start, end, key):
    """Index of the first direct child `key:` of the block lines[start+1:end], or None.
    Returns (index, child_indent, block_end)."""
    first = next((i for i in range(start + 1, end) if meaningful(lines[i])), None)
    if first is None:
        return None, None, None
    ci = indent(lines[first])
    for i in range(first, end):
        if not meaningful(lines[i]):
            continue
        if indent(lines[i]) < ci:
            break
        if indent(lines[i]) == ci and re.match(rf"{re.escape(key)}:(\s|$)", lines[i].strip()):
            stop = next((j for j in range(i + 1, end) if meaningful(lines[j]) and indent(lines[j]) <= ci), end)
            return i, ci, stop
    return None, ci, None


def set_scalar(lines, start, end, key, value):
    """Set `key: value` as a direct child of the block whose header is lines[start]."""
    i, ci, _ = child(lines, start, end, key)
    if i is not None:
        lines[i] = f"{' ' * ci}{key}: {value}\n"
        return end
    if ci is None:
        ci = indent(lines[start]) + 2
    lines.insert(start + 1, f"{' ' * ci}{key}: {value}\n")
    return end + 1


def main(argv):
    if len(argv) != 5:
        die("usage: bump-image.py <app> <service> <tag> <digest>")
    _, app, service, tag, digest = argv
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        die(f"digest {digest!r} is not sha256:<64 hex>")
    if tag == "latest" or not re.search(r"[0-9]", tag):
        die(f"tag {tag!r} is mutable-looking; hl-common rejects it (it must contain a digit)")

    chart = ROOT / "charts" / "apps" / app
    values_file, chart_file = chart / "values.yaml", chart / "Chart.yaml"
    if not chart_file.exists():
        die(f"application chart charts/apps/{app} does not exist; onboard it first")
    data = yaml.safe_load(values_file.read_text()) or {}
    if service not in data:
        die(f"charts/apps/{app}/values.yaml has no `{service}:` block; add the service first")
    if not (chart / "templates" / f"{service}.yaml").exists():
        die(f"charts/apps/{app}/templates/{service}.yaml is missing; add the service first")

    lines = values_file.read_text().splitlines(keepends=True)
    svc = next((i for i, l in enumerate(lines) if indent(l) == 0 and re.match(rf"{re.escape(service)}:\s*(#.*)?$", l.rstrip("\n"))), None)
    if svc is None:
        die(f"`{service}:` must be a block-style mapping at the top of values.yaml")
    svc_end = next((j for j in range(svc + 1, len(lines)) if meaningful(lines[j]) and indent(lines[j]) == 0), len(lines))

    wl, _, wl_end = child(lines, svc, svc_end, "workload")
    if wl is None:
        die(f"`{service}.workload` is missing in charts/apps/{app}/values.yaml")
    im, _, im_end = child(lines, wl, wl_end, "image")
    inline = "" if im is None else lines[im].split(":", 1)[1].strip()
    if im is None or (inline and not inline.startswith("#")):
        die(f"`{service}.workload.image` must exist in block style (one key per line)")

    im_end = set_scalar(lines, im, im_end, "tag", f'"{tag}"')
    set_scalar(lines, im, im_end, "digest", digest)
    values_file.write_text("".join(lines))

    check = yaml.safe_load(values_file.read_text())[service]["workload"]["image"]
    if check.get("tag") != tag or check.get("digest") != digest:
        die("edit did not produce the expected values; values.yaml left modified, inspect it")

    text = chart_file.read_text()
    m = re.search(r"^version:\s*\"?(\d+)\.(\d+)\.(\d+)\"?\s*$", text, re.M)
    if not m:
        die(f"charts/apps/{app}/Chart.yaml has no plain MAJOR.MINOR.PATCH version")
    new = f"{m[1]}.{m[2]}.{int(m[3]) + 1}"
    chart_file.write_text(text[: m.start()] + f"version: {new}" + text[m.end():])

    if (chart / "README.md.gotmpl").exists() or (chart / "README.md").exists():
        if not shutil.which("helm-docs"):
            die("helm-docs is not installed; the chart README must be regenerated (docs gate)")
        subprocess.run(["helm-docs", "--chart-search-root", str(chart), "--log-level", "warning"], cwd=ROOT, check=True, stdout=sys.stderr)
    print(new)


if __name__ == "__main__":
    main(sys.argv)
