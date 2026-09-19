#!/usr/bin/env bash
# Task P1-09. Clickops on purpose (CLAUDE.md #4) — run once as condor-bootstrap,
# never imported into Terraform/CloudFormation state. Appends every resource ID
# to manifest.json for teardown. Idempotent only in the sense that re-running
# creates new resources — this is a one-shot script, not IaC.
set -euo pipefail

REGION=us-east-1
APP_SUBNET_ID=subnet-07d4eaa7178b102dd
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HERE/../manifest.json"

# Windows Server 2016 + SQL Server 2019 Standard, license-included, still
# launchable in HOME_REGION. SQL 2016/2017 excluded per task (lifecycle
# findings not in the answer key); no Windows 2016 + SQL 2022 combo AMI
# exists in this region as of this run (checked, zero results).
AMI_ID=$(aws ec2 describe-images --region "$REGION" --owners amazon \
  --filters "Name=name,Values=Windows_Server-2016-English-Full-SQL_2019_Standard-*" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)
echo "AMI_ID=$AMI_ID"

# t2/t3 (burstable) are rejected outright by this AMI: "Microsoft SQL Server
# is not supported for the instance type" (UnsupportedOperation, confirmed
# with --dry-run). m5/c5/r5/m6i all accept it and none of those families
# offer anything smaller than .large. c5.large is the cheapest of those at
# $0.657/hr on-demand (US East N. Virginia, Windows + SQL Std, confirmed via
# the Pricing API) — well under the $1.50/hr cap.
INSTANCE_TYPE=c5.large

echo "== IAM (SSM core only) =="
cat > /tmp/facturacion-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name condor-facturacion-instance-role \
  --assume-role-policy-document file:///tmp/facturacion-trust.json --region "$REGION" >/dev/null
aws iam attach-role-policy --role-name condor-facturacion-instance-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam create-instance-profile --instance-profile-name condor-facturacion-instance-profile >/dev/null
aws iam add-role-to-instance-profile --instance-profile-name condor-facturacion-instance-profile \
  --role-name condor-facturacion-instance-role
sleep 10  # instance profile propagation

add_to_manifest() {
  local kind="$1" id="$2"
  python3 -c "
import json
m = json.load(open('$MANIFEST'))
m['resources'].append({'kind': '$kind', 'id': '$id', 'app': 'facturacion'})
json.dump(m, open('$MANIFEST', 'w'), indent=2)
"
}
add_to_manifest iam-role condor-facturacion-instance-role
add_to_manifest instance-profile condor-facturacion-instance-profile

echo "== EC2 condor-facturacion (tag app=facturacion only — AK-GRP-04) =="
INSTANCE_ID=$(aws ec2 run-instances --region "$REGION" \
  --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$APP_SUBNET_ID" \
  --iam-instance-profile Name=condor-facturacion-instance-profile \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=app,Value=facturacion}]' \
  --query 'Instances[0].InstanceId' --output text)
add_to_manifest ec2-instance "$INSTANCE_ID"

echo "== waiting for SSM registration =="
# Windows+SQL sysprep on first boot took ~15min live - the Linux-sized
# 7.5min loop (copied from reportes/deploy.sh) reported failure early.
for i in $(seq 1 120); do
  COUNT=$(aws ssm describe-instance-information --region "$REGION" \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query 'length(InstanceInformationList)' --output text)
  [ "$COUNT" = "1" ] && break
  sleep 20
done
[ "$COUNT" = "1" ] || { echo "instance never registered with SSM"; exit 1; }
echo "SSM-managed."

echo "== application inventory (needed for AWS:Application to show SQL Server) =="
aws ssm create-association --region "$REGION" \
  --name AWS-GatherSoftwareInventory \
  --targets "Key=InstanceIds,Values=$INSTANCE_ID" >/dev/null

echo "done"
echo "AMI_ID=$AMI_ID"
echo "INSTANCE_TYPE=$INSTANCE_TYPE"
echo "INSTANCE_ID=$INSTANCE_ID"
