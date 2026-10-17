#!/usr/bin/env python3
"""Policy 3 (FR-020, SC-007): no secret material in the repository."""
import re
from common import tracked_files, rel, finish

PATTERNS = [
    (re.compile(r"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----"), "private key"),
    (re.compile(r"\b(?:ghp|gho|ghs|github_pat)_[A-Za-z0-9_]{20,}"), "GitHub token"),
    (re.compile(r"\bhvs\.[A-Za-z0-9_-]{20,}"), "Vault token"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS access key"),
    (re.compile(r"(?im)^\s*(?:password|passwd|secret|token|apikey|api_key)\s*:\s*['\"]?(?!['\"]?\s*$)(?!\{\{)(?!<)[^\s'\"#]{4,}"), "literal credential value"),
    (re.compile(r"(?m)^kind:\s*Secret\s*$"), "Kubernetes Secret manifest"),
    (re.compile(r"(?m)^\s*client-certificate-data:|^\s*certificate-authority-data:"), "kubeconfig"),
]
SKIP_SUFFIX = (".png", ".jpg", ".tgz", ".lock")
SKIP_PATHS = ("tests/policy/", "specs/", "docs/", ".specify/", ".claude/")

failures = []
for f in tracked_files():
    r = rel(f)
    if r.endswith(SKIP_SUFFIX) or r.startswith(SKIP_PATHS) or r.endswith(".md"):
        continue
    try:
        text = f.read_text()
    except UnicodeDecodeError:
        continue
    for rx, label in PATTERNS:
        m = rx.search(text)
        if m:
            line = text.count("\n", 0, m.start()) + 1
            failures.append(f"{r}:{line}: {label}")
finish(failures)
