#!/usr/bin/env bash
# Task P1-12. Clickops on purpose (CLAUDE.md #4) — run once as condor-bootstrap,
# never imported into Terraform/CloudFormation state. Appends every resource ID
# to manifest.json for teardown. Idempotent only in the sense that re-running
# creates new resources — this is a one-shot script, not IaC.
set -euo pipefail

REGION=us-east-1
ACCT=337058058699
PROMO_SUBNET_ID=subnet-0ac2fbbc772bd2a34
PROMO_AZ=us-east-1a
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HERE/../manifest.json"
SRC_BUCKET="condor-promo-src-${ACCT}"

add_to_manifest() {
  local kind="$1" id="$2"
  python3 -c "
import json
m = json.load(open('$MANIFEST'))
m['resources'].append({'kind': '$kind', 'id': '$id', 'app': 'promo'})
json.dump(m, open('$MANIFEST', 'w'), indent=2)
"
}

echo "== EC2 condor-promo-2024 (no instance profile, no tags — AK-COV-04) =="
AMI_ID=$(aws ssm get-parameter --region "$REGION" \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' --output text)
INSTANCE_ID=$(aws ec2 run-instances --region "$REGION" \
  --image-id "$AMI_ID" --instance-type t3.micro \
  --subnet-id "$PROMO_SUBNET_ID" \
  --query 'Instances[0].InstanceId' --output text)
add_to_manifest ec2-instance "$INSTANCE_ID"

echo "== unattached EBS volume (AK-INF-07) =="
VOLUME_ID=$(aws ec2 create-volume --region "$REGION" \
  --availability-zone "$PROMO_AZ" --size 20 --volume-type gp3 \
  --query 'VolumeId' --output text)
add_to_manifest ebs-volume "$VOLUME_ID"

echo "== unassociated Elastic IP (AK-INF-07) =="
EIP_ALLOC_ID=$(aws ec2 allocate-address --region "$REGION" --domain vpc \
  --query 'AllocationId' --output text)
add_to_manifest elastic-ip "$EIP_ALLOC_ID"

echo "== source bucket (dead pipeline — AK-PIP-08) =="
aws s3api create-bucket --bucket "$SRC_BUCKET" --region "$REGION" >/dev/null
add_to_manifest s3-bucket "$SRC_BUCKET"
aws s3api put-bucket-versioning --bucket "$SRC_BUCKET" --region "$REGION" \
  --versioning-configuration Status=Enabled

zip -jq /tmp/promo-source.zip "$HERE/template.yaml"
aws s3 cp /tmp/promo-source.zip "s3://${SRC_BUCKET}/promo-source.zip" --region "$REGION" >/dev/null

echo "== IAM =="
cat > /tmp/promo-pipeline-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codepipeline.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name condor-promo-2024-pipeline-role \
  --assume-role-policy-document file:///tmp/promo-pipeline-trust.json --region "$REGION" >/dev/null
add_to_manifest iam-role condor-promo-2024-pipeline-role
cat > /tmp/promo-pipeline-policy.json <<EOF
{"Version":"2012-10-17","Statement":[
  {"Effect":"Allow","Action":["s3:GetObject","s3:GetObjectVersion","s3:GetBucketVersioning","s3:PutObject"],"Resource":["arn:aws:s3:::${SRC_BUCKET}","arn:aws:s3:::${SRC_BUCKET}/*"]},
  {"Effect":"Allow","Action":["cloudformation:CreateStack","cloudformation:UpdateStack","cloudformation:DeleteStack","cloudformation:DescribeStacks","cloudformation:CreateChangeSet","cloudformation:ExecuteChangeSet","cloudformation:DescribeChangeSet","cloudformation:DeleteChangeSet"],"Resource":"arn:aws:cloudformation:${REGION}:${ACCT}:stack/condor-promo-2024-web/*"},
  {"Effect":"Allow","Action":["iam:PassRole"],"Resource":"arn:aws:iam::${ACCT}:role/condor-promo-2024-cfn-role"}
]}
EOF
aws iam put-role-policy --role-name condor-promo-2024-pipeline-role \
  --policy-name pipeline-access --policy-document file:///tmp/promo-pipeline-policy.json

cat > /tmp/promo-cfn-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"cloudformation.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name condor-promo-2024-cfn-role \
  --assume-role-policy-document file:///tmp/promo-cfn-trust.json --region "$REGION" >/dev/null
add_to_manifest iam-role condor-promo-2024-cfn-role
cat > /tmp/promo-cfn-policy.json <<EOF
{"Version":"2012-10-17","Statement":[
  {"Effect":"Allow","Action":["ssm:PutParameter","ssm:DeleteParameter","ssm:GetParameters","ssm:AddTagsToResource"],"Resource":"arn:aws:ssm:${REGION}:${ACCT}:parameter/condor/promo-2024/*"}
]}
EOF
aws iam put-role-policy --role-name condor-promo-2024-cfn-role \
  --policy-name cfn-target-access --policy-document file:///tmp/promo-cfn-policy.json
sleep 10  # role propagation

echo "== CodePipeline condor-promo-2024 =="
PIPELINE_ROLE_ARN="arn:aws:iam::${ACCT}:role/condor-promo-2024-pipeline-role"
CFN_ROLE_ARN="arn:aws:iam::${ACCT}:role/condor-promo-2024-cfn-role"
cat > /tmp/promo-pipeline.json <<EOF
{
  "pipeline": {
    "name": "condor-promo-2024",
    "roleArn": "$PIPELINE_ROLE_ARN",
    "artifactStore": {"type": "S3", "location": "$SRC_BUCKET"},
    "stages": [
      {
        "name": "Source",
        "actions": [{
          "name": "Source",
          "actionTypeId": {"category": "Source", "owner": "AWS", "provider": "S3", "version": "1"},
          "configuration": {"S3Bucket": "$SRC_BUCKET", "S3ObjectKey": "promo-source.zip", "PollForSourceChanges": "false"},
          "outputArtifacts": [{"name": "SourceOutput"}]
        }]
      },
      {
        "name": "Deploy",
        "actions": [{
          "name": "Deploy",
          "actionTypeId": {"category": "Deploy", "owner": "AWS", "provider": "CloudFormation", "version": "1"},
          "configuration": {
            "ActionMode": "CREATE_UPDATE",
            "StackName": "condor-promo-2024-web",
            "TemplatePath": "SourceOutput::template.yaml",
            "Capabilities": "CAPABILITY_IAM",
            "RoleArn": "$CFN_ROLE_ARN"
          },
          "inputArtifacts": [{"name": "SourceOutput"}]
        }]
      }
    ]
  }
}
EOF
aws codepipeline create-pipeline --region "$REGION" --cli-input-json file:///tmp/promo-pipeline.json >/dev/null
add_to_manifest codepipeline condor-promo-2024

echo "== run the pipeline once =="
EXEC_ID=$(aws codepipeline start-pipeline-execution --region "$REGION" \
  --name condor-promo-2024 --query pipelineExecutionId --output text)
for i in $(seq 1 30); do
  STATUS=$(aws codepipeline get-pipeline-execution --region "$REGION" \
    --pipeline-name condor-promo-2024 --pipeline-execution-id "$EXEC_ID" \
    --query 'pipelineExecution.status' --output text)
  echo "  execution $EXEC_ID: $STATUS"
  case "$STATUS" in
    Succeeded) break ;;
    Failed|Stopped|Superseded) echo "pipeline did not succeed"; exit 1 ;;
  esac
  sleep 10
done
[ "$STATUS" = "Succeeded" ] || { echo "pipeline did not reach Succeeded in time"; exit 1; }

echo "== delete the target stack (dead pipeline — AK-PIP-08) =="
aws cloudformation delete-stack --region "$REGION" --stack-name condor-promo-2024-web
aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name condor-promo-2024-web

echo "done"
echo "INSTANCE_ID=$INSTANCE_ID"
echo "VOLUME_ID=$VOLUME_ID"
echo "EIP_ALLOC_ID=$EIP_ALLOC_ID"
