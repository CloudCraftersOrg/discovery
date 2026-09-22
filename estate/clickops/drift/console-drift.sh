#!/usr/bin/env bash
# Task P1-13, PLANTED: AK-INF-08. Runs from the operator's own workstation
# as dev.maria's static keys. Changes a parameter Terraform manages
# (estate/iac/pagos/aurora.tf's aws_rds_cluster_parameter_group.pagos
# already declares max_connections=150 - see that PR) directly via the
# CLI, without touching Terraform at all. `terraform plan` run afterwards
# as condor-bootstrap should show this parameter drifting back toward 150.
set -euo pipefail

REGION=us-east-1
SECRET_ARN="condor/harness/dev-maria"
PARAM_GROUP="condor-pagos-params"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LEDGER="$REPO_ROOT/estate/harness/ledger.jsonl"

if [ ! -f "$REPO_ROOT/estate/verify/history-start.json" ]; then
  echo "estate/verify/history-start.json is missing - P1-15 must run first. Stopping." >&2
  exit 1
fi

CREDS=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$SECRET_ARN" \
  --query SecretString --output text)
DEV_MARIA_KEY=$(echo "$CREDS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_key_id"])')
DEV_MARIA_SECRET=$(echo "$CREDS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["secret_access_key"])')

unset AWS_SESSION_TOKEN
export AWS_ACCESS_KEY_ID="$DEV_MARIA_KEY"
export AWS_SECRET_ACCESS_KEY="$DEV_MARIA_SECRET"
export AWS_DEFAULT_REGION="$REGION"

aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name "$PARAM_GROUP" \
  --parameters "ParameterName=max_connections,ParameterValue=200,ApplyMethod=immediate" \
  --region "$REGION" >/dev/null

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$(dirname "$LEDGER")"
python3 -c "
import json
with open('$LEDGER', 'a') as f:
    f.write(json.dumps({
        'ts': '$TS',
        'kind': 'planted_change',
        'task': 'P1-13',
        'answer_key_id': 'AK-INF-08',
        'actor': 'dev.maria',
        'change': 'condor-pagos-params max_connections 150 (terraform-declared) -> 200 (console, untracked)',
        'channel': 'console',
    }) + '\n')
"

echo "console drift done at $TS, recorded in $LEDGER."
echo "Verify: terraform -chdir=estate/iac/pagos plan (as condor-bootstrap) should show max_connections drift."
echo "Then: uv run estate/verify/check_planted.py --only P1-13"
