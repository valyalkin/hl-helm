#!/usr/bin/env python3
"""Hostname-collision edge case: two charts must not claim the same ingress host."""
import yaml
from common import ROOT, charts, render, rel, finish

# Production values for infrastructure charts = defaults + the file bootstrap/install.sh passes.
order = yaml.safe_load((ROOT / "bootstrap" / "install-order.yaml").read_text()) or {}
prod_values = {e["chart"]: ROOT / e["values"] for e in order.get("install", []) if e.get("values")}

owners = {}
failures = []
for tier, d in charts(("infrastructure", "apps")):
    # production values only: a chart's ci/ fixtures are examples and may reuse hosts
    for doc in yaml.safe_load_all(render(d, prod_values.get(rel(d)))):
        if doc and doc.get("kind") == "Ingress":
            for rule in doc["spec"].get("rules", []):
                host = rule.get("host")
                if host in owners and owners[host] != rel(d):
                    failures.append(f"host {host!r} claimed by both {owners[host]} and {rel(d)}")
                owners.setdefault(host, rel(d))
finish(failures)
