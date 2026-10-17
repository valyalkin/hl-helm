#!/usr/bin/env python3
"""Policy 1 (FR-021, SC-008): no rendered image uses a mutable tag.

Mutable = no tag, `latest`, or a tag with no digit — unless a digest pins it."""
import re
import yaml
from common import charts, render, fixtures, rel, finish


def images(node):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "image" and isinstance(v, str):
                yield v
            else:
                yield from images(v)
    elif isinstance(node, list):
        for v in node:
            yield from images(v)


def mutable(ref):
    if "@sha256:" in ref:
        return False
    last = ref.rsplit("/", 1)[-1]
    if ":" not in last:
        return True
    tag = last.split(":", 1)[1]
    return tag == "latest" or not re.search(r"\d", tag)


failures = []
for tier, d in charts(("bootstrap", "infrastructure", "apps")):
    for fx in fixtures(d):
        for doc in yaml.safe_load_all(render(d, fx)):
            for ref in images(doc or {}):
                if mutable(ref):
                    failures.append(f"{rel(d)}: image {ref!r} uses a mutable tag")
finish(sorted(set(failures)))
