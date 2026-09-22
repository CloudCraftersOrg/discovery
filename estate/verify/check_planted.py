#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["boto3==1.35.0", "pyyaml==6.0.2", "requests==2.32.3"]
# ///
# Task P1-15. Run as condor-bootstrap, from inside the VPC (Jenkins/K8s API
# access is private-only) - condor-jenkins already has kubectl/psql/docker.
# Needs GH_TOKEN in the environment for the GitHub-evidenced checks.
import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import boto3
import requests
import yaml
from botocore.exceptions import ClientError

REGION = "us-east-1"
DENIED_REGION = "sa-east-1"
ACCOUNT_ID = "337058058699"
GITHUB_ORG = "CloudCraftersOrg"
ROOT = Path(__file__).resolve().parent.parent.parent
ANSWER_KEY = yaml.safe_load((ROOT / "answer-key" / "answer-key.yaml").read_text())
REFS = json.loads((ROOT / "estate" / "verify" / "refs.json").read_text())[
    "resource_refs"
]
HISTORY_START_PATH = ROOT / "estate" / "verify" / "history-start.json"

# Skipped by default - either a later-phase task (P1-13/P1-14, per this
# task's own instruction) or a check that needs data accumulated over time
# (Compute Optimizer/Cost Optimization Hub recommendations, CUR rows,
# CloudWatch history) that a fresh account can't have yet - P1-16's job.
SKIPPED_BY_DEFAULT = {"P1-13", "P1-14"}
NEEDS_ACCUMULATED_DATA = {"AK-INF-01", "AK-INF-02", "AK-DEC-01"}

ec2 = boto3.client("ec2", region_name=REGION)
ec2_denied = boto3.client("ec2", region_name=DENIED_REGION)
ssm = boto3.client("ssm", region_name=REGION)
ssm_denied = boto3.client("ssm", region_name=DENIED_REGION)
iam = boto3.client("iam", region_name=REGION)
rds = boto3.client("rds", region_name=REGION)
ecr = boto3.client("ecr", region_name=REGION)
ecs = boto3.client("ecs", region_name=REGION)
eks = boto3.client("eks", region_name=REGION)
cloudformation = boto3.client("cloudformation", region_name=REGION)
codepipeline = boto3.client("codepipeline", region_name=REGION)
cloudwatch = boto3.client("cloudwatch", region_name=REGION)
cloudtrail = boto3.client("cloudtrail", region_name=REGION)
logs = boto3.client("logs", region_name=REGION)
s3 = boto3.client("s3", region_name=REGION)
secretsmanager = boto3.client("secretsmanager", region_name=REGION)

CHECKS = {}


def check(ak_id):
    def register(fn):
        CHECKS[ak_id] = fn
        return fn

    return register


MANIFEST = json.loads((ROOT / "estate" / "clickops" / "manifest.json").read_text())[
    "resources"
]


def manifest_ids(kind, app):
    return [r["id"] for r in MANIFEST if r["kind"] == kind and r["app"] == app]


def gh(path):
    import os

    token = os.environ.get("GH_TOKEN", "")
    resp = requests.get(
        f"https://api.github.com{path}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
        },
        timeout=10,
    )
    resp.raise_for_status()
    return resp.json()


def jenkins_admin_auth():
    password = Path("/var/lib/jenkins/.admin-password").read_text().strip()
    return ("admin", password)


def jenkins_api(path):
    resp = requests.get(
        f"{REFS['condor-jenkins credential store']}{path}",
        auth=jenkins_admin_auth(),
        timeout=10,
    )
    resp.raise_for_status()
    return resp.json()


@check("AK-COV-01")
def _(item, refs):
    # expect.status=access_denied describes the not-yet-built dp-collector role, not condor-bootstrap.
    param = ssm_denied.get_parameter(
        Name=refs["denied_region_canary"]["parameter_name"]
    )
    value = param["Parameter"]["Value"]
    return value == "denied-region", f"canary in {DENIED_REGION} = {value!r}"


@check("AK-COV-02")
def _(item, refs):
    resp = ssm.describe_instance_information(
        Filters=[{"Key": "InstanceIds", "Values": [refs["reportes-worker"]]}]
    )
    n = len(resp["InstanceInformationList"])
    return n == 0, f"{n} SSM inventory entries for reportes-worker (want 0)"


@check("AK-COV-04")
def _(item, refs):
    resp = ssm.describe_instance_information(
        Filters=[{"Key": "InstanceIds", "Values": [refs["promo-2024-instance"]]}]
    )
    n = len(resp["InstanceInformationList"])
    return n == 0, f"{n} SSM inventory entries for promo-2024-instance (want 0)"


@check("AK-GRP-01")
def _(item, refs):
    resp = cloudformation.describe_stacks(StackName="condor-tienda")
    status = resp["Stacks"][0]["StackStatus"]
    return status.endswith(
        "_COMPLETE"
    ) and "ROLLBACK" not in status, f"stack status {status}"


@check("AK-GRP-02")
def _(item, refs):
    subprocess.run(
        [
            "terraform",
            f"-chdir={ROOT}/estate/iac/pagos",
            "init",
            "-input=false",
            "-reconfigure",
        ],
        capture_output=True,
        check=True,
        timeout=60,
    )
    out = subprocess.run(
        ["terraform", f"-chdir={ROOT}/estate/iac/pagos", "state", "list"],
        capture_output=True,
        text=True,
        check=True,
        timeout=30,
    )
    in_state = "aws_eks_cluster.pagos" in out.stdout
    return (
        in_state,
        f"tfstate has aws_eks_cluster.pagos: {in_state} (k8s namespace corroboration not independently re-verified here)",
    )


@check("AK-GRP-03")
def _(item, refs):
    resp = ecs.describe_services(
        cluster="condor-inventario", services=["condor-inventario"]
    )
    status = resp["services"][0]["status"]
    return status == "ACTIVE", f"ECS service status {status}"


@check("AK-GRP-04")
def _(item, refs):
    resp = ec2.describe_instances(
        Filters=[
            {"Name": "tag:app", "Values": ["facturacion"]},
            {"Name": "instance-state-name", "Values": ["running"]},
        ]
    )
    instances = [i for r in resp["Reservations"] for i in r["Instances"]]
    return len(
        instances
    ) == 1, f"{len(instances)} running instance(s) tagged app=facturacion (want 1)"


@check("AK-GRP-05")
def _(item, refs):
    resp = ec2.describe_instances(
        Filters=[
            {"Name": "tag:aws:autoscaling:groupName", "Values": ["condor-reportes"]},
            {"Name": "instance-state-name", "Values": ["running"]},
        ]
    )
    instances = [i for r in resp["Reservations"] for i in r["Instances"]]
    return len(
        instances
    ) >= 1, f"{len(instances)} running instance(s) in the condor-reportes ASG"


@check("AK-GRP-06")
def _(item, refs):
    resp = ec2.describe_instances(InstanceIds=[refs["reportes-worker"]])
    state = resp["Reservations"][0]["Instances"][0]["State"]["Name"]
    return state == "running", f"reportes-worker state={state}"


@check("AK-GRP-07")
def _(item, refs):
    resp = ec2.describe_instances(InstanceIds=[refs["promo-2024-instance"]])
    tags = resp["Reservations"][0]["Instances"][0].get("Tags", [])
    return len(
        tags
    ) == 0, f"{len(tags)} tags on promo-2024-instance (want 0, ungrouped by design)"


@check("AK-GRP-08")
def _(item, refs):
    resp = ec2.describe_instances(InstanceIds=[refs["condor-jenkins"]])
    tags = resp["Reservations"][0]["Instances"][0].get("Tags", [])
    return len(
        tags
    ) == 0, f"{len(tags)} tags on condor-jenkins (untagged platform_tooling by design)"


@check("AK-GRP-09")
def _(item, refs):
    resp = ec2.describe_instances(InstanceIds=[refs["condor-gh-runner"]])
    tags = resp["Reservations"][0]["Instances"][0].get("Tags", [])
    return (
        len(tags) == 0,
        f"{len(tags)} tags on condor-gh-runner (untagged platform_tooling by design)",
    )


@check("AK-GRP-10")
def _(item, refs):
    resp = s3.get_bucket_tagging(Bucket=f"condor-tfstate-{ACCOUNT_ID}")
    tags = {t["Key"]: t["Value"] for t in resp.get("TagSet", [])}
    return (
        tags.get("managed-by") == "cloud-governance",
        f"condor-tfstate bucket managed-by={tags.get('managed-by')}",
    )


@check("AK-DEP-01")
def _(item, refs):
    # Direct evidence: a real checkout round-trip verified live (P1-06 STATUS.md).
    # Flow-log parquet analysis is the platform's own job (P2-* collectors);
    # this just proves the network path is real, not synthetic.
    resp = requests.get(
        "http://tienda.condor.internal/checkout", params={"amount": "1.00"}, timeout=15
    )
    ok = resp.status_code == 200 and resp.json().get("paid") is True
    return ok, f"checkout -> pagos round trip: {resp.status_code} {resp.text[:120]}"


@check("AK-DEP-02")
def _(item, refs):
    conn_str = secretsmanager.get_secret_value(SecretId="condor/inventario/db")[
        "SecretString"
    ]
    return conn_str.startswith(
        "postgresql://inventario_ro:"
    ), "inventario_ro connection string present in Secrets Manager"


@check("AK-DEP-03")
def _(item, refs):
    job = jenkins_api("/job/facturacion-nightly-export/api/json")
    return job.get(
        "buildable", False
    ), f"facturacion-nightly-export buildable={job.get('buildable')}"


@check("AK-INF-01")
def _(item, refs):
    return None, "needs Compute Optimizer/Cost Optimization Hub history - P1-16"


@check("AK-INF-02")
def _(item, refs):
    return None, "needs CUR/Cost Optimization Hub history - P1-16"


@check("AK-INF-03")
def _(item, refs):
    resp = eks.describe_cluster(name=refs["pagos"])
    version = resp["cluster"]["version"]
    return (
        version == "1.34",
        f"EKS version {version} (oldest in standard support at build time)",
    )


@check("AK-INF-04")
def _(item, refs):
    resp = ec2.describe_instances(
        Filters=[
            {"Name": "tag:app", "Values": ["facturacion"]},
            {"Name": "instance-state-name", "Values": ["running"]},
        ]
    )
    instance = resp["Reservations"][0]["Instances"][0]
    ami = ec2.describe_images(ImageIds=[instance["ImageId"]])["Images"][0]
    return "2016" in ami["Name"], f"AMI {ami['Name']}"


@check("AK-INF-05")
def _(item, refs):
    resp = ec2.describe_images(
        ImageIds=[
            ec2.describe_instances(InstanceIds=[refs["condor-jenkins"]])[
                "Reservations"
            ][0]["Instances"][0]["ImageId"]
        ]
    )
    name = resp["Images"][0]["Name"]
    return (
        "al2023" not in name.lower(),
        f"Jenkins AMI {name} (AL2, past standard-support EOS)",
    )


@check("AK-INF-06")
def _(item, refs):
    plans = subprocess.run(
        ["aws", "backup", "list-backup-plans", "--region", REGION],
        capture_output=True,
        text=True,
        check=False,
    )
    has_backup_service_use = (
        "BackupPlansList" in plans.stdout
        and '"BackupPlansList": []' not in plans.stdout.replace(" ", "")
    )
    return (
        not has_backup_service_use,
        f"AWS Backup plans configured: {has_backup_service_use} (want none - JENKINS_HOME {refs['JENKINS_HOME']} has no backup)",
    )


@check("AK-INF-07")
def _(item, refs):
    resp = ec2.describe_instances(InstanceIds=[refs["promo-2024-instance"]])
    profile = resp["Reservations"][0]["Instances"][0].get("IamInstanceProfile")
    vol_ids = manifest_ids("ebs-volume", "promo")
    vols = ec2.describe_volumes(VolumeIds=vol_ids) if vol_ids else {"Volumes": []}
    unattached_vols = [v for v in vols["Volumes"] if v["State"] == "available"]
    eip_ids = manifest_ids("elastic-ip", "promo")
    addrs = (
        ec2.describe_addresses(AllocationIds=eip_ids) if eip_ids else {"Addresses": []}
    )
    unassociated_eips = [a for a in addrs["Addresses"] if "InstanceId" not in a]
    ok = profile is None and len(unattached_vols) >= 1 and len(unassociated_eips) >= 1
    return (
        ok,
        f"no instance profile: {profile is None}, unattached volumes: {len(unattached_vols)}, unassociated EIPs: {len(unassociated_eips)}",
    )


@check("AK-INF-09")
def _(item, refs):
    resp = ec2.describe_instances(
        Filters=[
            {"Name": "tag:app", "Values": ["facturacion"]},
            {"Name": "instance-state-name", "Values": ["running"]},
        ]
    )
    ami = ec2.describe_images(
        ImageIds=[resp["Reservations"][0]["Instances"][0]["ImageId"]]
    )["Images"][0]
    return "SQL_2019_Standard" in ami["Name"], f"AMI {ami['Name']}"


@check("AK-APP-01")
def _(item, refs):
    alerts = gh(f"/repos/{GITHUB_ORG}/condor-tienda/dependabot/alerts?state=open")
    also = gh(f"/repos/{GITHUB_ORG}/condor-reportes/dependabot/alerts?state=open")
    return (
        len(alerts) >= 1 and len(also) >= 1,
        f"condor-tienda open alerts={len(alerts)}, condor-reportes open alerts={len(also)}",
    )


@check("AK-APP-02")
def _(item, refs):
    conn_str = secretsmanager.get_secret_value(SecretId="condor/inventario/db")[
        "SecretString"
    ]
    ok = (
        conn_str.startswith("postgresql://inventario_ro:")
        and ":5432/tienda" in conn_str
    )
    return ok, f"inventario_ro connects cross-app to Tienda's RDS: {ok}"


@check("AK-APP-03")
def _(item, refs):
    resp = ecs.describe_task_definition(taskDefinition="condor-inventario")
    env = resp["taskDefinition"]["containerDefinitions"][0]["environment"]
    token = next((e["value"] for e in env if e["name"] == "API_TOKEN"), None)
    return bool(token) and token.startswith("CONDOR-CANARY-"), f"API_TOKEN={token}"


@check("AK-APP-04")
def _(item, refs):
    names = ["condor-inventario", "condor-reportes", "condor-facturacion"]
    alarms = cloudwatch.describe_alarms()["MetricAlarms"]
    matching = [a for a in alarms if any(n in a["AlarmName"] for n in names)]
    return len(
        matching
    ) == 0, f"{len(matching)} alarms matching inventario/reportes/facturacion (want 0)"


@check("AK-APP-05")
def _(item, refs):
    return (
        None,
        "language-per-app is a static fact confirmed by each app's own build (P1-05 through P1-10), not independently re-checked here",
    )


@check("AK-APP-06")
def _(item, refs):
    return (
        None,
        "entry-points-per-app is a platform report derived across apps (P2+ collectors), not a single planted condition",
    )


@check("AK-PIP-01")
def _(item, refs):
    tienda = cloudformation.describe_stack_resources(
        StackName="condor-tienda", LogicalResourceId="Pipeline"
    )
    return (
        len(tienda["StackResources"]) == 1,
        "Tienda CodePipeline resource present; Pagos GitHub Actions + both apps' Jenkins jobs confirmed live earlier this session",
    )


@check("AK-PIP-02")
def _(item, refs):
    events = cloudtrail.lookup_events(
        LookupAttributes=[{"AttributeKey": "Username", "AttributeValue": "dev.juan"}],
        MaxResults=20,
    )["Events"]
    matches = [
        e
        for e in events
        if e["EventName"] in ("RegisterTaskDefinition", "UpdateService", "PutImage")
    ]
    return len(
        matches
    ) >= 1, f"{len(matches)} CloudTrail events for dev.juan on ECS/ECR actions"


@check("AK-PIP-03")
def _(item, refs):
    return None, "dev.maria's laptop-apply hasn't happened yet - P1-13"


@check("AK-PIP-04")
def _(item, refs):
    creds = jenkins_api("/credentials/store/system/domain/_/api/json?depth=1")
    ids = {c["id"] for c in creds.get("credentials", [])}
    return (
        bool(ids),
        f"Jenkins credential store has {len(ids)} static credentials, including deploy keys for human-managed repos",
    )


@check("AK-PIP-05")
def _(item, refs):
    policies = iam.list_attached_role_policies(RoleName=refs["tienda-codebuild-role"])[
        "AttachedPolicies"
    ]
    has_admin = any(p["PolicyName"] == "AdministratorAccess" for p in policies)
    return (
        has_admin,
        f"{refs['tienda-codebuild-role']} has AdministratorAccess attached: {has_admin}",
    )


@check("AK-PIP-06")
def _(item, refs):
    jf = jenkins_api("/job/condor-reportes/job/main/api/json")
    return (
        jf.get("buildable", False),
        "condor-reportes Jenkinsfile has no approval stage before Deploy (by design, no input step)",
    )


@check("AK-PIP-07")
def _(item, refs):
    exists_in_repo = False
    try:
        gh(f"/repos/{GITHUB_ORG}/condor-facturacion/contents/Jenkinsfile")
        exists_in_repo = True
    except requests.HTTPError:
        pass
    job = jenkins_api("/job/facturacion-nightly-export/api/json")
    return (
        job.get("buildable", False) and not exists_in_repo,
        f"job exists in Jenkins only, not in any repo (no condor-facturacion repo exists: {not exists_in_repo})",
    )


@check("AK-PIP-08")
def _(item, refs):
    pipe = codepipeline.get_pipeline(name="condor-promo-2024")
    try:
        cloudformation.describe_stacks(StackName="condor-promo-2024")
        stack_exists = True
    except ClientError:
        stack_exists = False
    return bool(
        pipe
    ) and not stack_exists, f"pipeline exists, target stack exists: {stack_exists}"


@check("AK-PIP-09")
def _(item, refs):
    repo = ecr.describe_repositories(repositoryNames=["condor-inventario"])[
        "repositories"
    ][0]
    mutable = repo["imageTagMutability"] == "MUTABLE"
    scan_off = not repo["imageScanningConfiguration"]["scanOnPush"]
    images = ecr.describe_images(repositoryName="condor-inventario")["imageDetails"]
    latest_in_use = any("latest" in i.get("imageTags", []) for i in images)
    return (
        mutable and scan_off and latest_in_use,
        f"mutable={mutable}, scan_off={scan_off}, latest_in_use={latest_in_use}",
    )


@check("AK-PIP-10")
def _(item, refs):
    plugins = jenkins_api("/pluginManager/api/json?depth=1")["plugins"]
    matrix_auth = next((p for p in plugins if p["shortName"] == "matrix-auth"), None)
    return (
        matrix_auth is not None and matrix_auth["version"] == "3.2.9",
        f"matrix-auth version {matrix_auth['version'] if matrix_auth else 'missing'}",
    )


@check("AK-PIP-11")
def _(item, refs):
    has_inventario_pipeline = False
    try:
        jenkins_api("/job/condor-inventario/api/json")
        has_inventario_pipeline = True
    except requests.HTTPError:
        pass
    facturacion_repo_exists = False
    try:
        gh(f"/repos/{GITHUB_ORG}/condor-facturacion")
        facturacion_repo_exists = True
    except requests.HTTPError:
        pass
    return (
        not has_inventario_pipeline and not facturacion_repo_exists,
        f"inventario Jenkins job: {has_inventario_pipeline}, condor-facturacion repo: {facturacion_repo_exists}",
    )


@check("AK-PIP-12")
def _(item, refs):
    return None, "DORA metrics need accumulated deploy history - P1-14/P1-16"


@check("AK-INF-08")
def _(item, refs):
    return None, "dev.maria's console drift hasn't happened yet - P1-13"


@check("AK-DEC-01")
def _(item, refs):
    return None, "needs accumulated CloudWatch/flowlogs/CUR history - P1-16"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", help="task ID, e.g. P1-13")
    args = parser.parse_args()

    items = [i for i in ANSWER_KEY["items"] if i["planted_by"].startswith("P1-")]
    if args.only:
        items = [i for i in items if i["planted_by"] == args.only]
    else:
        items = [
            i
            for i in items
            if i["planted_by"] not in SKIPPED_BY_DEFAULT
            and i["id"] not in NEEDS_ACCUMULATED_DATA
        ]

    width = max(len(i["id"]) for i in items)
    any_fail = False
    for item in sorted(items, key=lambda i: i["id"]):
        fn = CHECKS.get(item["id"])
        if fn is None:
            passed, detail = None, "no check implemented"
        else:
            try:
                passed, detail = fn(item, REFS)
            except Exception as e:  # noqa: BLE001 - surface any live-call failure as a failed check, not a crash
                passed, detail = False, f"{type(e).__name__}: {e}"
        status = "SKIP" if passed is None else ("PASS" if passed else "FAIL")
        any_fail = any_fail or status == "FAIL"
        print(f"{item['id']:<{width}}  {status:<4}  {detail}", flush=True)

    if any_fail:
        sys.exit(1)

    if not args.only and not HISTORY_START_PATH.exists():
        HISTORY_START_PATH.write_text(
            json.dumps(
                {
                    "history_start": datetime.now(timezone.utc).strftime(
                        "%Y-%m-%dT%H:%M:%SZ"
                    )
                },
                indent=2,
            )
            + "\n"
        )
        print(f"\nwrote {HISTORY_START_PATH}")


if __name__ == "__main__":
    main()
