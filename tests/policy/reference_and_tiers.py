#!/usr/bin/env python3
"""Policy 4 (FR-048, FR-056, FR-060, SC-026).

- the reference chart renders against the current hl-common
- no bootstrap-tier chart contains a secret reference (cold-rebuild deadlock rule)
- the Argo CD ApplicationSet manages only charts/apps/* (tier match)"""
import re
import yaml
from common import ROOT, charts, render, fixtures, rel, finish

failures = []

ref = ROOT / "charts" / "apps" / "nginx"
if not ref.is_dir():
    failures.append("charts/apps/nginx: reference chart is missing")
else:
    for fx in fixtures(ref):
        render(ref, fx)  # exits non-zero with a message if it no longer renders

for tier, d in charts(("bootstrap",)):
    for f in d.rglob("*"):
        if f.is_file() and "/charts/" not in str(f.relative_to(d)) and f.suffix in (".yaml", ".yml", ".tpl"):
            text = f.read_text()
            if re.search(r"VaultStaticSecret|VaultDynamicSecret", text) or re.search(r"(?m)^secrets:\s*\S", text):
                failures.append(f"{rel(f)}: bootstrap-tier chart {d.name!r} declares a secret reference; "
                                "bootstrap components may not read from Vault (FR-056)")

for appset in list((ROOT / "argocd").glob("*.y*ml")) if (ROOT / "argocd").is_dir() else []:
    for doc in yaml.safe_load_all(appset.read_text()):
        if not doc or doc.get("kind") not in ("ApplicationSet", "Application"):
            continue
        text = yaml.dump(doc)
        for path in re.findall(r"charts/[A-Za-z0-9_./*-]+", text):
            if not path.startswith("charts/apps/"):
                failures.append(f"{rel(appset)}: Argo CD manages {path!r}, which is above the "
                                "application tier (FR-030, FR-060)")
finish(failures)
