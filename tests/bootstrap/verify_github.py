#!/usr/bin/env python3
"""Verify the GitHub environments of the deploy workflow.

Live test, run locally (tests/run.sh --live). Needs GITHUB_TOKEN, which
run.sh takes from the GitHub CLI login when unset. Read-only.
"""

import json
import os
import sys
import urllib.error
import urllib.request

REPO = "technogix/infrastructure"
EXPECTED_SECRETS = {
    "OVH_CLIENT_ID", "OVH_CLIENT_SECRET",
    "STATE_S3_ACCESS_KEY_ID", "STATE_S3_SECRET_ACCESS_KEY",
    "SOPS_AGE_KEY",
}

results = []


def check(label, ok, detail=""):
    results.append(ok)
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f" ({detail})" if detail else ""))


def api(path):
    req = urllib.request.Request(f"https://api.github.com/{path}", headers={
        "Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
        "Accept": "application/vnd.github+json",
    })
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def secret_names(env):
    return {s["name"] for s in api(f"repos/{REPO}/environments/{env}/secrets")["secrets"]}


def main():
    if not os.environ.get("GITHUB_TOKEN"):
        sys.exit("GITHUB_TOKEN is not set (run through tests/run.sh --live, or `gh auth login`).")

    envs = {e["name"]: e for e in api(f"repos/{REPO}/environments")["environments"]}
    check("environments plan and production exist", {"plan", "production"} <= envs.keys(),
          ", ".join(sorted(envs)))
    if not {"plan", "production"} <= envs.keys():
        return 1

    print("== production")
    prod = envs["production"]
    rules = {r["type"]: r for r in prod.get("protection_rules", [])}
    reviewers = [r["reviewer"]["login"] for r in rules.get("required_reviewers", {}).get("reviewers", [])]
    check("requires an approval", bool(reviewers), ", ".join(reviewers) or "no reviewer")
    check("admins cannot bypass the approval", prod.get("can_admins_bypass") is False)
    policy = prod.get("deployment_branch_policy") or {}
    check("deployments restricted to custom branch rules", policy.get("custom_branch_policies") is True)
    branches = [p["name"] for p in api(f"repos/{REPO}/environments/production/deployment-branch-policies")["branch_policies"]]
    check("only main can deploy", branches == ["main"], ", ".join(branches))

    print("== plan")
    check("no approval needed (pull requests)", "required_reviewers" not in
          {r["type"] for r in envs["plan"].get("protection_rules", [])})

    print("== main branch ruleset")
    rulesets = [r for r in api(f"repos/{REPO}/rulesets") if r["name"] == "main"]
    check("ruleset main exists", len(rulesets) == 1)
    if rulesets:
        rs = api(f"repos/{REPO}/rulesets/{rulesets[0]['id']}")
        rules = {r["type"]: r.get("parameters", {}) for r in rs.get("rules", [])}
        check("ruleset is enforced", rs.get("enforcement") == "active", rs.get("enforcement"))
        check("targets the default branch",
              rs.get("conditions", {}).get("ref_name", {}).get("include") == ["~DEFAULT_BRANCH"])
        check("nobody can bypass it", not rs.get("bypass_actors"))
        check("changes only through a pull request", "pull_request" in rules)
        check("squash merges only",
              rules.get("pull_request", {}).get("allowed_merge_methods") == ["squash"])
        contexts = {c["context"] for c in rules.get("required_status_checks", {}).get("required_status_checks", [])}
        check("check and plan-result must pass", contexts == {"check", "plan-result"}, ", ".join(sorted(contexts)))
        for rule, label in (("non_fast_forward", "no force push"), ("deletion", "main cannot be deleted"),
                            ("required_linear_history", "linear history")):
            check(label, rule in rules)

    print("== Secrets (names only: values cannot be read back)")
    for env in ("plan", "production"):
        names = secret_names(env)
        check(f"{env}: exactly the expected secrets", names == EXPECTED_SECRETS,
              f"missing {sorted(EXPECTED_SECRETS - names)}, extra {sorted(names - EXPECTED_SECRETS)}"
              if names != EXPECTED_SECRETS else "")
    repo_secrets = {s["name"] for s in api(f"repos/{REPO}/actions/secrets")["secrets"]}
    check("no repository-level secret (they would bypass the environments)", not repo_secrets,
          ", ".join(sorted(repo_secrets)))

    failed = results.count(False)
    print(f"\n{len(results) - failed}/{len(results)} checks passed.")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except urllib.error.HTTPError as e:
        sys.exit(f"GitHub API error: HTTP {e.code} on {e.url}")
