#!/usr/bin/env bash
# Task P1-13, PLANTED: AK-PIP-03. Runs from the operator's own workstation
# (no VPC access needed - EKS/S3 are public AWS API endpoints), as
# dev.maria's static keys, against this same discovery repo checkout.
#
# Edits estate/iac/pagos/eks.tf's node group max_size in place, applies
# just that one resource, then discards the edit with `git checkout --` so
# nothing about it is ever committed to this repo or condor-pagos - the
# point of the finding is that tfstate now disagrees with what's checked
# in, with no CI run behind it.
set -euo pipefail

REGION=us-east-1
SECRET_ARN="condor/harness/dev-maria"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PAGOS_DIR="$REPO_ROOT/estate/iac/pagos"
LEDGER="$REPO_ROOT/estate/harness/ledger.jsonl"
EKS_TF="$PAGOS_DIR/eks.tf"

if [ ! -f "$REPO_ROOT/estate/verify/history-start.json" ]; then
  echo "estate/verify/history-start.json is missing - P1-15 must run first. Stopping." >&2
  exit 1
fi

if [ -n "$(git -C "$REPO_ROOT" status --porcelain -- "$EKS_TF")" ]; then
  echo "$EKS_TF already has uncommitted changes - resolve that before running this. Stopping." >&2
  exit 1
fi

CREDS=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$SECRET_ARN" \
  --query SecretString --output text)
DEV_MARIA_KEY=$(echo "$CREDS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_key_id"])')
DEV_MARIA_SECRET=$(echo "$CREDS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["secret_access_key"])')

sed -i.bak 's/max_size     = 2/max_size     = 3/' "$EKS_TF"
rm -f "$EKS_TF.bak"

cleanup() {
  git -C "$REPO_ROOT" checkout -- "$EKS_TF"
}
trap cleanup EXIT

unset AWS_SESSION_TOKEN
export AWS_ACCESS_KEY_ID="$DEV_MARIA_KEY"
export AWS_SECRET_ACCESS_KEY="$DEV_MARIA_SECRET"
export AWS_DEFAULT_REGION="$REGION"

terraform -chdir="$PAGOS_DIR" init -input=false -reconfigure
terraform -chdir="$PAGOS_DIR" apply -auto-approve -target=aws_eks_node_group.pagos \
  -var condor_account_id=337058058699

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
        'answer_key_id': 'AK-PIP-03',
        'actor': 'dev.maria',
        'change': 'aws_eks_node_group.pagos scaling_config.max_size 2 -> 3',
        'channel': 'tfstate_write',
    }) + '\n')
"

echo "laptop apply done at $TS, recorded in $LEDGER. eks.tf reverted (git checkout by the trap above)."
echo "Next: estate/clickops/drift/console-drift.sh"
