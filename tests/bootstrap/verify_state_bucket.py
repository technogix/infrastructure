#!/usr/bin/env python3
"""Verify that the Terraform state bucket is usable and protected.

Live test, run locally after `terraform apply` in bootstrap/:

    python -m pip install -r tests/requirements.txt
    tests/run.sh --live

Needs terraform and the OVH admin credentials (~/.ovh.conf). The S3 keys are
read from the bootstrap outputs (local state).

Every check writes under the `_healthcheck/` prefix only. Objects written
there stay in the bucket for the retention period (a few KB per run).
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

ROOT = Path(__file__).resolve().parents[2]
BOOTSTRAP = ROOT / "bootstrap"
BACKEND_CONFIG = ROOT / "backend.hcl"
ENDPOINT = "https://s3.gra.io.cloud.ovh.net"
REGION = "gra"
HEALTHCHECK_KEY = "_healthcheck/terraform.tfstate"

results = []


def check(label, ok, detail=""):
    results.append(ok)
    print(f"[{'PASS' if ok else 'FAIL'}] {label}" + (f" ({detail})" if detail else ""))


def terraform(args, cwd, creds=None):
    env = dict(os.environ, TF_IN_AUTOMATION="1", TF_INPUT="0")
    if creds:
        env["AWS_ACCESS_KEY_ID"] = creds["access_key_id"]
        env["AWS_SECRET_ACCESS_KEY"] = creds["secret_access_key"]
    return subprocess.run(["terraform", *args], cwd=cwd, env=env,
                          capture_output=True, text=True)


def s3_client(creds):
    return boto3.client(
        "s3", endpoint_url=ENDPOINT, region_name=REGION,
        aws_access_key_id=creds["access_key_id"],
        aws_secret_access_key=creds["secret_access_key"],
        config=Config(request_checksum_calculation="when_required",
                      response_checksum_validation="when_required"),
    )


def must_be_refused(label, fn):
    try:
        fn()
        check(label, False, "accepted")
    except ClientError as e:
        check(label, True, f"refused: {e.response['Error']['Code']}")


def main():
    out = terraform(["output", "-json"], BOOTSTRAP)
    if out.returncode != 0:
        sys.exit(f"Cannot read bootstrap outputs:\n{out.stderr}")
    outputs = json.loads(out.stdout)
    bucket = outputs["bucket_name"]["value"]
    writer = outputs["s3_credentials"]["value"]["writer"]
    reader = outputs["s3_credentials"]["value"]["reader"]

    print(f"== Bucket configuration ({bucket})")
    plan = terraform(["plan", "-detailed-exitcode", "-no-color"], BOOTSTRAP)
    check("bootstrap code matches the real bucket and users (no drift)",
          plan.returncode == 0, f"terraform plan exit code {plan.returncode}")

    print("== Terraform backend, as used by the CI")
    with tempfile.TemporaryDirectory() as tmp:
        Path(tmp, "main.tf").write_text(
            'terraform {\n  backend "s3" {\n    key = "%s"\n  }\n}\n\n'
            'variable "run" {\n  type = string\n}\n\n'
            'resource "terraform_data" "probe" {\n  input = var.run\n}\n' % HEALTHCHECK_KEY,
            encoding="utf-8")
        run_id = os.urandom(4).hex()

        r = terraform(["init", "-no-color", f"-backend-config={BACKEND_CONFIG}"], tmp, writer)
        check("writer: terraform init", r.returncode == 0, r.stderr.strip()[-200:])
        r = terraform(["apply", "-auto-approve", "-no-color", f"-var=run={run_id}"], tmp, writer)
        check("writer: terraform apply (state write, lock take and release)",
              r.returncode == 0, r.stderr.strip()[-200:])
        r = terraform(["plan", "-no-color", "-lock=false", "-detailed-exitcode",
                       f"-var=run={run_id}"], tmp, reader)
        check("reader: terraform plan without lock reads the state",
              r.returncode == 0, r.stderr.strip()[-200:])
        r = terraform(["plan", "-no-color", f"-var=run={run_id}"], tmp, reader)
        check("reader: cannot take the state lock",
              r.returncode != 0 and "Error acquiring the state lock" in r.stderr)

    w, rd = s3_client(writer), s3_client(reader)
    version = w.head_object(Bucket=bucket, Key=HEALTHCHECK_KEY)["VersionId"]

    print("== Locking primitive used by Terraform")
    try:
        w.put_object(Bucket=bucket, Key=HEALTHCHECK_KEY, Body=b"{}", IfNoneMatch="*")
        check("conditional write on an existing key is rejected", False, "accepted")
    except ClientError as e:
        code = e.response["ResponseMetadata"]["HTTPStatusCode"]
        check("conditional write on an existing key is rejected", code == 412, f"HTTP {code}")

    print("== Protection against deletion")
    must_be_refused("reader: cannot write", lambda: rd.put_object(
        Bucket=bucket, Key="_healthcheck/reader-write", Body=b"x"))
    must_be_refused("writer: cannot delete a state version", lambda: w.delete_object(
        Bucket=bucket, Key=HEALTHCHECK_KEY, VersionId=version))
    must_be_refused("writer: cannot delete a state version with governance bypass",
                    lambda: w.delete_object(Bucket=bucket, Key=HEALTHCHECK_KEY,
                                            VersionId=version, BypassGovernanceRetention=True))
    must_be_refused("writer: cannot delete the bucket", lambda: w.delete_bucket(Bucket=bucket))
    # Re-applies the expected configuration: harmless even if wrongly accepted.
    must_be_refused("writer: cannot change the Object Lock configuration",
                    lambda: w.put_object_lock_configuration(
                        Bucket=bucket, ObjectLockConfiguration={
                            "ObjectLockEnabled": "Enabled",
                            "Rule": {"DefaultRetention": {"Mode": "COMPLIANCE", "Days": 30}}}))

    failed = results.count(False)
    print(f"\n{len(results) - failed}/{len(results)} checks passed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
