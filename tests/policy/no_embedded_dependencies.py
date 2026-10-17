#!/usr/bin/env python3
"""Policy 2 (FR-066, SC-033): an application chart never embeds its dependencies.

- an application-tier chart may depend only on the hl-common library
- no chart commits a vendored subchart directory
- no chart defines a hl-common.* template of its own (a chart-local copy stops receiving
  convention changes)"""
import re
import yaml
from common import ROOT, charts, rel, tracked_files, finish

failures = []
for tier, d in charts():
    meta = yaml.safe_load((d / "Chart.yaml").read_text())
    if tier == "apps":
        for dep in meta.get("dependencies") or []:
            if dep["name"] != "hl-common":
                failures.append(f"{rel(d / 'Chart.yaml')}: application chart depends on {dep['name']!r}; "
                                "only hl-common is allowed (FR-066)")
    if tier != "library":
        for tpl in (d / "templates").rglob("*") if (d / "templates").is_dir() else []:
            if tpl.is_file() and re.search(r'define\s+"hl-common\.', tpl.read_text()):
                failures.append(f"{rel(tpl)}: chart-local copy of a hl-common template")

for f in tracked_files():
    parts = f.relative_to(ROOT).parts
    if len(parts) > 4 and parts[0] == "charts" and parts[3] == "charts":
        failures.append(f"{rel(f)}: vendored subchart committed inside a chart")
finish(failures)
