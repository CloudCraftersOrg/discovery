#!/usr/bin/env bash
# Task P1-13. Clickops on purpose (CLAUDE.md #4) - creates the dev.maria
# identity that estate/clickops/drift/laptop-apply.sh and console-drift.sh
# act as. Runs as condor-bootstrap.
#
# dev.maria's own policy is deliberately narrower than the task text's two
# bullets ("read/write on pagos/*, plus permissions to modify
# condor-pagos-params") - that alone can't make `terraform apply` on the
# node group succeed, since a targeted apply still refreshes and mutates
# everything in that resource's dependency graph: the EKS cluster (for
# vpc_config), the node IAM role and its three policy attachments, and the
# network layer's remote state (read-only, for subnet_ids - eks.tf line 78).
# Added those explicitly below rather than leave the laptop-apply step to
# fail on a live AccessDenied; if anything further surfaces once it
# actually runs, extend this policy the same way, in a small follow-up.
set -euo pipefail

REGION=us-east-1
ACCOUNT_ID=337058058699
BOUNDARY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/condor-sandbox-boundary"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HERE/../manifest.json"

add_to_manifest() {
  local kind="$1" id="$2"
  python3 -c "
import json
m = json.load(open('$MANIFEST'))
m['resources'].append({'kind': '$kind', 'id': '$id', 'app': 'pagos'})
json.dump(m, open('$MANIFEST', 'w'), indent=2)
"
}

echo "== dev.maria (PLANTED: AK-PIP-04) =="
aws iam create-user --user-name dev.maria --permissions-boundary "$BOUNDARY_ARN" --region "$REGION" >/dev/null
add_to_manifest iam-user dev.maria

cat > /tmp/dev-maria-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TfStatePagosReadWrite",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:GetObjectVersion"],
      "Resource": "arn:aws:s3:::condor-tfstate-${ACCOUNT_ID}/pagos/*"
    },
    {
      "Sid": "TfStateListPagosPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::condor-tfstate-${ACCOUNT_ID}",
      "Condition": {"StringLike": {"s3:prefix": ["pagos/*", "pagos"]}}
    },
    {
      "Sid": "TfStateNetworkReadOnly",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::condor-tfstate-${ACCOUNT_ID}/estate/network.tfstate"
    },
    {
      "Sid": "PagosNodeGroupApply",
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:DescribeNodegroup",
        "eks:UpdateNodegroupConfig",
        "eks:ListTagsForResource",
        "eks:TagResource",
        "eks:UntagResource"
      ],
      "Resource": [
        "arn:aws:eks:${REGION}:${ACCOUNT_ID}:cluster/condor-pagos",
        "arn:aws:eks:${REGION}:${ACCOUNT_ID}:nodegroup/condor-pagos/condor-pagos-nodes/*"
      ]
    },
    {
      "Sid": "PagosNodeRoleRefreshOnly",
      "Effect": "Allow",
      "Action": ["iam:GetRole", "iam:ListAttachedRolePolicies", "iam:ListRolePolicies"],
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/condor-pagos-node-role"
    },
    {
      "Sid": "PagosParams",
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBClusterParameterGroups",
        "rds:DescribeDBClusterParameters",
        "rds:ModifyDBClusterParameterGroup"
      ],
      "Resource": "arn:aws:rds:${REGION}:${ACCOUNT_ID}:cluster-pg:condor-pagos-params"
    }
  ]
}
EOF

aws iam put-user-policy --user-name dev.maria --policy-name pagos-laptop-and-drift \
  --policy-document file:///tmp/dev-maria-policy.json --region "$REGION"
rm -f /tmp/dev-maria-policy.json

ACCESS_KEY_JSON=$(aws iam create-access-key --user-name dev.maria --region "$REGION")
add_to_manifest iam-access-key "$(echo "$ACCESS_KEY_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["AccessKey"]["AccessKeyId"])')"

echo "$ACCESS_KEY_JSON" | python3 -c '
import json, sys
k = json.load(sys.stdin)["AccessKey"]
print(json.dumps({"access_key_id": k["AccessKeyId"], "secret_access_key": k["SecretAccessKey"]}))
' > /tmp/dev-maria-secret.json

aws secretsmanager create-secret --region "$REGION" --name condor/harness/dev-maria \
  --secret-string file:///tmp/dev-maria-secret.json >/dev/null
rm -f /tmp/dev-maria-secret.json
add_to_manifest secretsmanager-secret condor/harness/dev-maria

echo "dev.maria ready. Next: estate/clickops/drift/laptop-apply.sh, then console-drift.sh."
