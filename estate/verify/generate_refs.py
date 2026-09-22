#!/usr/bin/env python3
# Task P1-15. Regenerates refs.json's resource_refs from Terraform outputs,
# Tienda's CFN stack, and manifest.json. Run as condor-bootstrap.
import json
import subprocess
from pathlib import Path

REGION = "us-east-1"
ACCOUNT_ID = "337058058699"
ROOT = Path(__file__).resolve().parent.parent.parent
REFS_PATH = ROOT / "estate" / "verify" / "refs.json"
MANIFEST_PATH = ROOT / "estate" / "clickops" / "manifest.json"


def aws(*args):
    out = subprocess.run(
        ["aws", *args, "--region", REGION, "--output", "json"],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(out.stdout) if out.stdout.strip() else None


def tf_output(module):
    subprocess.run(
        [
            "terraform",
            f"-chdir={ROOT}/estate/iac/{module}",
            "init",
            "-input=false",
            "-reconfigure",
        ],
        capture_output=True,
        check=True,
    )
    out = subprocess.run(
        ["terraform", f"-chdir={ROOT}/estate/iac/{module}", "output", "-json"],
        capture_output=True,
        text=True,
        check=True,
    )
    return {k: v["value"] for k, v in json.loads(out.stdout).items()}


def manifest_id(kind, app):
    manifest = json.loads(MANIFEST_PATH.read_text())
    matches = [
        r["id"] for r in manifest["resources"] if r["kind"] == kind and r["app"] == app
    ]
    if len(matches) != 1:
        raise SystemExit(
            f"expected exactly one manifest match for kind={kind} app={app}, got {matches}"
        )
    return matches[0]


def main():
    jenkins = tf_output("jenkins")
    runner = tf_output("runner")
    pagos = tf_output("pagos")

    jenkins_volumes = aws(
        "ec2",
        "describe-volumes",
        "--filters",
        f"Name=attachment.instance-id,Values={jenkins['jenkins_instance_id']}",
        "Name=attachment.device,Values=/dev/sdf",
    )
    jenkins_home_volume = jenkins_volumes["Volumes"][0]["VolumeId"]

    tienda_codebuild_role = aws(
        "cloudformation",
        "describe-stack-resource",
        "--stack-name",
        "condor-tienda",
        "--logical-resource-id",
        "CodeBuildRole",
    )["StackResourceDetail"]["PhysicalResourceId"]

    tienda_db = aws(
        "rds",
        "describe-db-instances",
        "--db-instance-identifier",
        "condor-tienda-db",
    )["DBInstances"][0]["DBInstanceArn"]

    resource_refs = {
        "condor-jenkins": jenkins["jenkins_instance_id"],
        "condor-jenkins credential store": f"http://{jenkins['jenkins_private_ip']}:8080",
        "JENKINS_HOME": jenkins_home_volume,
        "condor-jenkins-instance-profile": f"arn:aws:iam::{ACCOUNT_ID}:instance-profile/condor-jenkins-instance-profile",
        "condor-gh-runner": runner["runner_instance_id"],
        "condor-tienda-db": tienda_db,
        "tienda-codebuild-role": tienda_codebuild_role,
        "condor-pagos-db": f"arn:aws:rds:{REGION}:{ACCOUNT_ID}:cluster:condor-pagos-db",
        "pagos": pagos["cluster_name"],
        "condor-inventario ECR repo": f"arn:aws:ecr:{REGION}:{ACCOUNT_ID}:repository/{manifest_id('ecr-repository', 'inventario')}",
        "reportes-worker": manifest_id("ec2-instance", "reportes"),
        "promo-2024-instance": manifest_id("ec2-instance", "promo"),
        "denied_region_canary": {
            "parameter_name": "/condor/canary",
            "region": "sa-east-1",
        },
    }

    current = json.loads(REFS_PATH.read_text())
    current["resource_refs"] = resource_refs
    REFS_PATH.write_text(json.dumps(current, indent=2, sort_keys=True) + "\n")
    print(f"wrote {len(resource_refs)} resource_refs to {REFS_PATH}")


if __name__ == "__main__":
    main()
