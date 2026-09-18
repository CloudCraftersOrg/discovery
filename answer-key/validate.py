#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["jsonschema==4.23.0", "pyyaml==6.0.2"]
# ///
"""Validate answer-key.yaml against schema.json, and check that every
planted_by references a real task ID in PLAN.md.

Usage: uv run answer-key/validate.py
"""

import json
import re
import sys
from pathlib import Path

import jsonschema
import yaml

ROOT = Path(__file__).resolve().parent.parent
ANSWER_KEY = Path(__file__).resolve().parent / "answer-key.yaml"
SCHEMA = Path(__file__).resolve().parent / "schema.json"
PLAN = ROOT / "PLAN.md"

TASK_ID_RE = re.compile(r"\b(P[1-5]-[0-9]{2})\b")


def load_plan_task_ids() -> set[str]:
    text = PLAN.read_text(encoding="utf-8")
    return set(TASK_ID_RE.findall(text))


def main() -> int:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    doc = yaml.safe_load(ANSWER_KEY.read_text(encoding="utf-8"))
    items = doc["items"]

    validator = jsonschema.Draft202012Validator(schema)
    errors = []

    for item in items:
        for err in validator.iter_errors(item):
            errors.append(f"{item.get('id', '<no id>')}: {err.message}")

    task_ids = load_plan_task_ids()
    for item in items:
        planted_by = item.get("planted_by")
        if planted_by not in task_ids:
            errors.append(
                f"{item['id']}: planted_by '{planted_by}' is not a task ID in PLAN.md"
            )

    ids = [item["id"] for item in items]
    duplicates = {i for i in ids if ids.count(i) > 1}
    if duplicates:
        errors.append(f"duplicate ids: {sorted(duplicates)}")

    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1

    print(f"OK: {len(items)} items, all valid, all planted_by resolve to real tasks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
