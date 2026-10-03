#!/usr/bin/env bash
# Decrypts every stacks/**/*.enc.yaml (SOPS) into a gitignored *.auto.tfvars.json
# next to it, which Terraform loads automatically.
#
# In GitHub Actions, every decrypted value is registered with ::add-mask:: so
# that it shows up as *** in the (public) logs of the following steps.
#
# Needs `sops` and the age private key (SOPS_AGE_KEY, SOPS_AGE_KEY_FILE or the
# default sops key file).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

find "$root/stacks" -name '*.enc.yaml' -print0 | while IFS= read -r -d '' enc; do
  out="${enc%.enc.yaml}.auto.tfvars.json"
  if ! sops decrypt --output-type json "$enc" > "$out.tmp"; then
    rm -f "$out.tmp"
    echo "Failed to decrypt ${enc#"$root"/}" >&2
    exit 1
  fi
  mv "$out.tmp" "$out"

  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    python3 - "$out" <<'PY'
import json
import sys


def mask(value):
    if isinstance(value, dict):
        for v in value.values():
            mask(v)
    elif isinstance(value, list):
        for v in value:
            mask(v)
    elif isinstance(value, str) and value:
        print(f"::add-mask::{value}")


with open(sys.argv[1], encoding="utf-8") as f:
    mask(json.load(f))
PY
  fi

  echo "Decrypted ${enc#"$root"/}"
done
