#!/usr/bin/env bash
# Runs the test suite.
#
#   tests/run.sh          Offline tests: no credentials, no OVHcloud call (CI).
#   tests/run.sh --live   Offline tests, then live checks against OVHcloud
#                         (local only: needs ~/.ovh.conf, the bootstrap state
#                         and tests/requirements.txt installed).
#
# Set PYTHON to choose the interpreter, e.g. PYTHON=.venv/Scripts/python.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# $PYTHON if set (e.g. a virtualenv), else the first interpreter that actually
# runs (on Windows, `python3` may be a Microsoft Store placeholder).
python_bin=""
for candidate in ${PYTHON:-} python3 python; do
  if "$candidate" -c "import sys" > /dev/null 2>&1; then
    python_bin="$candidate"
    break
  fi
done
if [ -z "$python_bin" ]; then
  echo "Python 3 not found." >&2
  exit 1
fi
failed=0

# Collapsible sections in GitHub Actions, plain headers elsewhere.
section() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::group::$1"; else echo "== $1"; fi; }
endsection() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::endgroup::"; fi; }

run() {
  section "$1"
  shift
  if "$@"; then
    endsection
  else
    endsection
    echo "FAILED: $*" >&2
    failed=1
  fi
}

# Terraform only accepts a test directory inside the configuration, so the
# tests of tests/stacks/<name>/ are copied into stacks/<name>/.tests/ (gitignored).
terraform_tests() {
  local stack="$1" status=0
  rm -rf "stacks/$stack/.tests"
  cp -r "tests/stacks/$stack" "stacks/$stack/.tests"
  terraform -chdir="stacks/$stack" init -backend=false -input=false > /dev/null &&
    terraform -chdir="stacks/$stack" test -test-directory=.tests || status=$?
  rm -rf "stacks/$stack/.tests"
  return "$status"
}

run "Plan guard" "$python_bin" -m unittest discover -s tests/scripts -v

for dir in tests/stacks/*/; do
  stack="$(basename "$dir")"
  run "Terraform tests: $stack" terraform_tests "$stack"
done

if [ "${1:-}" = "--live" ]; then
  # The bootstrap (and its GitHub checks) read GitHub through the CLI login.
  if [ -z "${GITHUB_TOKEN:-}" ] && command -v gh > /dev/null 2>&1; then
    GITHUB_TOKEN="$(gh auth token 2> /dev/null || true)"
    export GITHUB_TOKEN
  fi
  if "$python_bin" -c "import boto3" > /dev/null 2>&1; then
    for check in tests/bootstrap/verify_*.py; do
      run "Live: $(basename "$check" .py)" "$python_bin" "$check"
    done
  else
    echo "FAILED: boto3 missing for $python_bin. Run: $python_bin -m pip install -r tests/requirements.txt" >&2
    failed=1
  fi
fi

if [ "$failed" -ne 0 ]; then
  echo "Some tests failed." >&2
  exit 1
fi
echo "All tests passed."
