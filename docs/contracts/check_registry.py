#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["pyyaml==6.0.2"]
# ///
"""Every collector named in answer-key.yaml's evidence_sources must have an
entry in collectors.yaml, and every collectors.yaml entry's evidence_for
must match what the answer key actually cites.

Usage: uv run docs/contracts/check_registry.py
"""

import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent.parent
ANSWER_KEY = ROOT / "answer-key" / "answer-key.yaml"
COLLECTORS = Path(__file__).resolve().parent / "collectors.yaml"


def main() -> int:
    answer_key = yaml.safe_load(ANSWER_KEY.read_text(encoding="utf-8"))
    registry = yaml.safe_load(COLLECTORS.read_text(encoding="utf-8"))["collectors"]

    used = {}
    for item in answer_key["items"]:
        for source in item["evidence_sources"]:
            used.setdefault(source, set()).add(item["id"])

    errors = []

    for name in used:
        if name not in registry:
            errors.append(f"'{name}' is cited in answer-key.yaml but has no entry in collectors.yaml")

    for name, entry in registry.items():
        expected = used.get(name, set())
        actual = set(entry.get("evidence_for", []))
        if actual != expected:
            errors.append(
                f"'{name}': collectors.yaml evidence_for {sorted(actual)} != "
                f"answer-key.yaml actual usage {sorted(expected)}"
            )

    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1

    print(f"OK: {len(used)} collectors cited in the answer key, all registered and in sync")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
