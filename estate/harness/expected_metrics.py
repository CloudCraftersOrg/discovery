#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["boto3==1.35.0", "requests==2.32.3"]
# ///
"""Task P1-14. Computes per-app DORA metrics (deploy frequency, change
failure rate, lead time) from estate/harness/ledger.jsonl, joined with
each app's real pipeline run results (AK-PIP-12's ground truth for
Phase 4's own independent computation - tolerance_source in the answer
key). Only entries with ts >= history_start count.

tienda deploys through CodePipeline, pagos through GitHub Actions,
reportes through Jenkins only - so the join differs per app. Jenkins'
REST API is VPC-private; run this from condor-jenkins like
check_planted.py, or lead time for reportes falls back to the ledger's
own commit-to-fix gap as its only distance measure.
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import boto3
import requests

REGION = "us-east-1"
GITHUB_ORG = "CloudCraftersOrg"
ROOT = Path(__file__).resolve().parent.parent.parent
LEDGER_PATH = ROOT / "estate" / "harness" / "ledger.jsonl"
HISTORY_START_PATH = ROOT / "estate" / "verify" / "history-start.json"
REFS_PATH = ROOT / "estate" / "verify" / "refs.json"
OUT_PATH = ROOT / "answer-key" / "expected" / "dora.json"

APPS = ["tienda", "pagos", "reportes"]
DEPLOY_KINDS = {"commit", "fix", "manual_push"}
FAILURE_KINDS = {"expected_build_fail", "expected_deploy_fail"}

codepipeline = boto3.client("codepipeline", region_name=REGION)


def load_history_start():
    if not HISTORY_START_PATH.exists():
        print(f"{HISTORY_START_PATH} is missing - run P1-15 first.", file=sys.stderr)
        sys.exit(1)
    raw = json.loads(HISTORY_START_PATH.read_text())["history_start"]
    return datetime.fromisoformat(raw.replace("Z", "+00:00"))


def load_ledger(history_start):
    entries = []
    for line in LEDGER_PATH.read_text().splitlines():
        if not line.strip():
            continue
        entry = json.loads(line)
        ts = datetime.fromisoformat(entry["ts"].replace("Z", "+00:00"))
        if ts >= history_start:
            entry["_ts"] = ts
            entries.append(entry)
    return entries


def tienda_deploy_completed_at(sha):
    paginator = codepipeline.get_paginator("list_pipeline_executions")
    for page in paginator.paginate(pipelineName="condor-tienda"):
        for execution in page["pipelineExecutionSummaries"]:
            revisions = execution.get("sourceRevisions", [])
            matches = any(r.get("revisionId") == sha for r in revisions)
            if matches and execution["status"] == "Succeeded":
                return execution["lastUpdateTime"]
    return None


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


def pagos_deploy_completed_at(sha):
    runs = gh(f"/repos/{GITHUB_ORG}/condor-pagos/actions/runs?head_sha={sha}")[
        "workflow_runs"
    ]
    for run in runs:
        if run["path"].endswith("deploy.yml") and run["conclusion"] == "success":
            return datetime.fromisoformat(run["updated_at"].replace("Z", "+00:00"))
    return None


def jenkins_admin_auth():
    return ("admin", Path("/var/lib/jenkins/.admin-password").read_text().strip())


def reportes_deploy_completed_at(sha, refs):
    try:
        builds = requests.get(
            f"{refs['condor-jenkins credential store']}/job/condor-reportes/job/main/api/json?tree=builds[number,result,timestamp,duration,changeSet[items[commitId]]]",
            auth=jenkins_admin_auth(),
            timeout=10,
        ).json()["builds"]
    except (requests.RequestException, KeyError, FileNotFoundError):
        return None
    for build in builds:
        commits = [c["commitId"] for c in build.get("changeSet", {}).get("items", [])]
        if sha in commits and build["result"] == "SUCCESS":
            return datetime.fromtimestamp(
                (build["timestamp"] + build["duration"]) / 1000, tz=timezone.utc
            )
    return None


COMPLETED_AT = {
    "tienda": tienda_deploy_completed_at,
    "pagos": pagos_deploy_completed_at,
}


def app_metrics(app, entries, refs):
    app_entries = [e for e in entries if e.get("app") == app]
    deploys = [e for e in app_entries if e["kind"] in DEPLOY_KINDS]
    failures = [e for e in app_entries if e["kind"] in FAILURE_KINDS]
    total_attempts = len(deploys) + len(failures)

    lookup = COMPLETED_AT.get(app)
    lead_times_hours = []
    for e in deploys:
        if e.get("sha") is None:
            continue
        completed = (
            lookup(e["sha"]) if lookup else reportes_deploy_completed_at(e["sha"], refs)
        )
        if completed is not None:
            lead_times_hours.append((completed - e["_ts"]).total_seconds() / 3600)

    if app_entries:
        span_days = max(
            (
                max(e["_ts"] for e in app_entries) - min(e["_ts"] for e in app_entries)
            ).total_seconds()
            / 86400,
            1,
        )
    else:
        span_days = 1

    return {
        "deploy_frequency_per_day": round(len(deploys) / span_days, 4),
        "deploy_count": len(deploys),
        "change_failure_rate": round(len(failures) / total_attempts, 4)
        if total_attempts
        else 0.0,
        "lead_time_hours": round(sum(lead_times_hours) / len(lead_times_hours), 4)
        if lead_times_hours
        else None,
        "lead_time_samples": len(lead_times_hours),
    }


def main():
    history_start = load_history_start()
    entries = load_ledger(history_start)
    refs = json.loads(REFS_PATH.read_text())["resource_refs"]

    result = {
        "history_start": history_start.isoformat().replace("+00:00", "Z"),
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "apps": {app: app_metrics(app, entries, refs) for app in APPS},
    }

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(result, indent=2) + "\n")
    print(f"wrote {OUT_PATH}")


if __name__ == "__main__":
    main()
