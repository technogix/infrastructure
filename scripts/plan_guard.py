#!/usr/bin/env python3
"""Fail if a Terraform plan destroys or replaces a protected (stateful) resource.

Usage: plan_guard.py <plan.json> [protected-resource-types.txt]
The plan JSON comes from `terraform show -json tfplan`.
"""

import fnmatch
import json
import sys
from pathlib import Path

DEFAULT_POLICY = Path(__file__).resolve().parent.parent / "policy" / "protected-resource-types.txt"


def load_patterns(path):
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    return [l.strip() for l in lines if l.strip() and not l.strip().startswith("#")]


def is_protected(resource_type, patterns):
    return any(fnmatch.fnmatchcase(resource_type, p) for p in patterns)


def main(argv):
    if len(argv) not in (2, 3):
        print(__doc__, file=sys.stderr)
        return 2

    plan = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    patterns = load_patterns(argv[2] if len(argv) == 3 else DEFAULT_POLICY)

    counts = {"create": 0, "update": 0, "replace": 0, "delete": 0}
    violations = []

    for rc in plan.get("resource_changes", []):
        if rc.get("mode") != "managed":
            continue
        actions = rc["change"]["actions"]
        if "delete" in actions and "create" in actions:
            kind = "replace"
        elif "delete" in actions:
            kind = "delete"
        elif "create" in actions:
            kind = "create"
        elif "update" in actions:
            kind = "update"
        else:
            continue
        counts[kind] += 1
        if kind in ("delete", "replace") and is_protected(rc["type"], patterns):
            violations.append(f"{rc['address']} ({kind})")

    print("Plan: {create} to create, {update} to update, {replace} to replace, "
          "{delete} to delete.".format(**counts))

    if violations:
        print("\nERROR: this plan would destroy stateful resources:", file=sys.stderr)
        for v in violations:
            print(f"  - {v}", file=sys.stderr)
        print("\nRefusing to continue. See policy/protected-resource-types.txt.",
              file=sys.stderr)
        return 1

    print("Guard OK: no stateful resource is destroyed or replaced.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
