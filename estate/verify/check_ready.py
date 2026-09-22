#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["boto3==1.35.0", "duckdb==1.1.3"]
# ///
"""Task P1-16. Confirms the estate has produced enough data for Phase 4
to test the platform against - nothing there can pass before this.
Prints every unmet condition and exits 1; never sleep-loops, since the
underlying gaps (Compute Optimizer's own recommendation window is up to
14 days, the harness ledger needs real time to accumulate) can only be
closed by the operator re-running this later, not by waiting inline.
"""

import json
import socket
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import boto3
import duckdb

REGION = "us-east-1"
ACCOUNT_ID = "337058058699"
ROOT = Path(__file__).resolve().parent.parent.parent
LEDGER_PATH = ROOT / "estate" / "harness" / "ledger.jsonl"
HISTORY_START_PATH = ROOT / "estate" / "verify" / "history-start.json"
DORA_PATH = ROOT / "answer-key" / "expected" / "dora.json"
REFS = json.loads((ROOT / "estate" / "verify" / "refs.json").read_text())[
    "resource_refs"
]

ec2 = boto3.client("ec2", region_name=REGION)
elbv2 = boto3.client("elbv2", region_name=REGION)
autoscaling = boto3.client("autoscaling", region_name=REGION)
ecs = boto3.client("ecs", region_name=REGION)
compute_optimizer = boto3.client("compute-optimizer", region_name=REGION)
cost_optimization_hub = boto3.client("cost-optimization-hub", region_name="us-east-1")

FAILURES = []
CHECKS = []


def check(label):
    def register(fn):
        def wrapped():
            ok, detail = fn()
            print(f"{'PASS' if ok else 'FAIL'}  {label}: {detail}")
            if not ok:
                FAILURES.append(label)
            return ok

        CHECKS.append(wrapped)
        return wrapped

    return register


def duckdb_s3_connection():
    session = boto3.Session(region_name=REGION)
    creds = session.get_credentials().get_frozen_credentials()
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs;")
    con.execute(f"SET s3_region='{REGION}';")
    con.execute(f"SET s3_access_key_id='{creds.access_key}';")
    con.execute(f"SET s3_secret_access_key='{creds.secret_key}';")
    if creds.token:
        con.execute(f"SET s3_session_token='{creds.token}';")
    return con


@check("check_planted.py --only P1-13")
def _():
    result = subprocess.run(
        [
            "uv",
            "run",
            str(ROOT / "estate" / "verify" / "check_planted.py"),
            "--only",
            "P1-13",
        ],
        capture_output=True,
        check=False,
    )
    return result.returncode == 0, f"exit {result.returncode}"


@check("check_planted.py --only P1-14")
def _():
    result = subprocess.run(
        [
            "uv",
            "run",
            str(ROOT / "estate" / "verify" / "check_planted.py"),
            "--only",
            "P1-14",
        ],
        capture_output=True,
        check=False,
    )
    return result.returncode == 0, f"exit {result.returncode}"


@check("CUR 2.0 has a partition with Tienda resource IDs")
def _():
    con = duckdb_s3_connection()
    path = f"s3://condor-cur-{ACCOUNT_ID}/condor-cur2/condor-cur2/data/*/*.parquet"
    try:
        (count,) = con.execute(
            f"SELECT count(*) FROM read_parquet('{path}') WHERE line_item_resource_id ILIKE '%tienda%'"
        ).fetchone()
    except duckdb.IOException as e:
        return False, f"no CUR2 data delivered yet ({e})"
    return count > 0, f"{count} CUR2 rows reference a Tienda resource ID"


@check("Compute Optimizer has a recommendation for the Tienda ASG")
def _():
    asgs = autoscaling.describe_auto_scaling_groups()["AutoScalingGroups"]
    tienda_asg = next(
        a["AutoScalingGroupName"]
        for a in asgs
        if "tienda" in a["AutoScalingGroupName"].lower()
    )
    recs = compute_optimizer.get_auto_scaling_group_recommendations(
        accountIds=[ACCOUNT_ID]
    )["autoScalingGroupRecommendations"]
    match = [r for r in recs if tienda_asg in r["autoScalingGroupArn"]]
    return bool(match), f"{len(match)} recommendation(s) for {tienda_asg}"


@check("Cost Optimization Hub has at least one recommendation")
def _():
    items = cost_optimization_hub.list_recommendations(maxResults=5)["items"]
    return bool(items), f"{len(items)} recommendation(s) account-wide"


def resolve_ips():
    asgs = autoscaling.describe_auto_scaling_groups()["AutoScalingGroups"]
    tienda_asg = next(a for a in asgs if "tienda" in a["AutoScalingGroupName"].lower())
    tienda_instance_ids = [i["InstanceId"] for i in tienda_asg["Instances"]]
    tienda_ips = [
        i["PrivateIpAddress"]
        for r in ec2.describe_instances(InstanceIds=tienda_instance_ids)["Reservations"]
        for i in r["Instances"]
    ]

    pagos_nlb = next(
        lb
        for lb in elbv2.describe_load_balancers()["LoadBalancers"]
        if "pagos" in lb["LoadBalancerName"].lower()
    )
    pagos_ips = list(
        {ip[4][0] for ip in socket.getaddrinfo(pagos_nlb["DNSName"], None)}
    )

    reportes_alb = next(
        lb
        for lb in elbv2.describe_load_balancers()["LoadBalancers"]
        if "reportes" in lb["LoadBalancerName"].lower()
    )
    reportes_ips = list(
        {ip[4][0] for ip in socket.getaddrinfo(reportes_alb["DNSName"], None)}
    )

    worker_ip = ec2.describe_instances(InstanceIds=[REFS["reportes-worker"]])[
        "Reservations"
    ][0]["Instances"][0]["PrivateIpAddress"]

    tienda_rds_host = "condor-tienda-db.calscauowkvr.us-east-1.rds.amazonaws.com"
    tienda_rds_ips = list(
        {ip[4][0] for ip in socket.getaddrinfo(tienda_rds_host, None)}
    )

    task_arns = ecs.list_tasks(cluster="condor-inventario")["taskArns"]
    inventario_ips = []
    if task_arns:
        tasks = ecs.describe_tasks(cluster="condor-inventario", tasks=task_arns)[
            "tasks"
        ]
        for task in tasks:
            for attachment in task.get("attachments", []):
                for detail in attachment.get("details", []):
                    if detail["name"] == "privateIPv4Address":
                        inventario_ips.append(detail["value"])

    return {
        "tienda": tienda_ips,
        "pagos": pagos_ips,
        "reportes": reportes_ips,
        "worker": [worker_ip],
        "tienda_rds": tienda_rds_ips,
        "inventario": inventario_ips,
    }


def flow_exists(con, path, src_ips, dst_ips):
    if not src_ips or not dst_ips:
        return False
    src_list = ",".join(f"'{ip}'" for ip in src_ips)
    dst_list = ",".join(f"'{ip}'" for ip in dst_ips)
    (count,) = con.execute(
        f"""
        SELECT count(*) FROM read_parquet('{path}')
        WHERE action = 'ACCEPT'
          AND ((srcaddr IN ({src_list}) AND dstaddr IN ({dst_list}))
            OR (srcaddr IN ({dst_list}) AND dstaddr IN ({src_list})))
        """
    ).fetchone()
    return count > 0


@check(
    "Flow logs show accepted Tienda<->Pagos, worker<->Reportes, Inventario<->Tienda-RDS traffic"
)
def _():
    ips = resolve_ips()
    today = datetime.now(timezone.utc).strftime("%Y/%m/%d")
    path = f"s3://condor-flowlogs-{ACCOUNT_ID}/AWSLogs/{ACCOUNT_ID}/vpcflowlogs/{REGION}/{today}/*/*.parquet"
    con = duckdb_s3_connection()
    try:
        tienda_pagos = flow_exists(con, path, ips["tienda"], ips["pagos"])
        worker_reportes = flow_exists(con, path, ips["worker"], ips["reportes"])
        inventario_rds = flow_exists(con, path, ips["inventario"], ips["tienda_rds"])
    except duckdb.IOException as e:
        return False, f"no flow log data for today yet ({e})"
    ok = tienda_pagos and worker_reportes and inventario_rds
    return (
        ok,
        f"tienda->pagos={tienda_pagos}, worker->reportes={worker_reportes}, inventario->tienda-rds={inventario_rds}",
    )


@check("Harness ledger has >=8 commits, each app has >=2 deploys, since history_start")
def _():
    if not HISTORY_START_PATH.exists():
        return False, f"{HISTORY_START_PATH} missing"
    history_start = datetime.fromisoformat(
        json.loads(HISTORY_START_PATH.read_text())["history_start"].replace(
            "Z", "+00:00"
        )
    )
    deploy_kinds = {"commit", "fix", "manual_push"}
    per_app = {"tienda": 0, "pagos": 0, "reportes": 0}
    total = 0
    for line in LEDGER_PATH.read_text().splitlines():
        if not line.strip():
            continue
        entry = json.loads(line)
        ts = datetime.fromisoformat(entry["ts"].replace("Z", "+00:00"))
        if ts < history_start or entry.get("kind") not in deploy_kinds:
            continue
        total += 1
        if entry.get("app") in per_app:
            per_app[entry["app"]] += 1
    ok = total >= 8 and all(v >= 2 for v in per_app.values())
    return ok, f"total={total} (want >=8), per_app={per_app} (want each >=2)"


@check("answer-key/expected/dora.json exists")
def _():
    return DORA_PATH.exists(), str(DORA_PATH)


def main():
    results = [fn() for fn in CHECKS]
    if all(results):
        print("\nready.")
        sys.exit(0)
    print(f"\nnot ready - {len(FAILURES)} unmet condition(s): {', '.join(FAILURES)}")
    sys.exit(1)


if __name__ == "__main__":
    main()
