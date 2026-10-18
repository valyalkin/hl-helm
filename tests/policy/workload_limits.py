#!/usr/bin/env python3
"""Platform constraint: every container in every rendered workload declares resource requests
and a memory limit (the node is shared and unbounded workloads can take the cluster down)."""
import yaml
from common import charts, render, fixtures, rel, finish

KINDS = ("Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob", "ReplicaSet")


def pod_spec(doc):
    spec = doc["spec"]
    if doc["kind"] == "CronJob":
        spec = spec["jobTemplate"]["spec"]
    return spec["template"]["spec"]


failures = []
for tier, d in charts(("bootstrap", "infrastructure", "apps")):
    for fx in fixtures(d):
        for doc in yaml.safe_load_all(render(d, fx)):
            if not doc or doc.get("kind") not in KINDS:
                continue
            hook = ((doc.get("metadata") or {}).get("annotations") or {}).get("helm.sh/hook", "")
            if "test" in hook:
                continue
            ps = pod_spec(doc)
            for c in ps.get("containers", []) + ps.get("initContainers", []):
                res = c.get("resources") or {}
                if not (res.get("limits") or {}).get("memory"):
                    failures.append(f"{rel(d)}: {doc['kind']}/{doc['metadata']['name']} container "
                                    f"{c['name']!r} has no limits.memory")
                if not (res.get("requests") or {}):
                    failures.append(f"{rel(d)}: {doc['kind']}/{doc['metadata']['name']} container "
                                    f"{c['name']!r} has no resource requests")
finish(sorted(set(failures)))
