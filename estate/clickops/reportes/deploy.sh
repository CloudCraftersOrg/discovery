#!/usr/bin/env bash
# Task P1-10. Clickops on purpose (CLAUDE.md #4) — run once as condor-bootstrap,
# never imported into Terraform/CloudFormation state. Appends every resource ID
# to manifest.json for teardown. Idempotent only in the sense that re-running
# creates new resources — this is a one-shot script, not IaC.
set -euo pipefail

REGION=us-east-1
ACCT=337058058699
VPC_ID=vpc-06f069857cd5a3612
APP_SUBNETS=(subnet-07d4eaa7178b102dd subnet-053689a1cf888e29e)
HOSTED_ZONE_ID=Z10047152ET2OKEP623WQ
VPC_CIDR=10.20.0.0/16
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HERE/../manifest.json"

add_to_manifest() {
  local kind="$1" id="$2"
  python3 -c "
import json
m = json.load(open('$MANIFEST'))
m['resources'].append({'kind': '$kind', 'id': '$id', 'app': 'reportes'})
json.dump(m, open('$MANIFEST', 'w'), indent=2)
"
}

echo "== security groups =="
ALB_SG=$(aws ec2 create-security-group --region "$REGION" \
  --group-name condor-reportes-alb --description "condor-reportes ALB" --vpc-id "$VPC_ID" \
  --query GroupId --output text)
add_to_manifest security-group "$ALB_SG"
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$ALB_SG" \
  --protocol tcp --port 80 --cidr "$VPC_CIDR" >/dev/null

INSTANCE_SG=$(aws ec2 create-security-group --region "$REGION" \
  --group-name condor-reportes-instances --description "condor-reportes instances" --vpc-id "$VPC_ID" \
  --query GroupId --output text)
add_to_manifest security-group "$INSTANCE_SG"
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$INSTANCE_SG" \
  --protocol tcp --port 8080 --source-group "$ALB_SG" >/dev/null

echo "== IAM =="
cat > /tmp/instance-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name condor-reportes-instance-role \
  --assume-role-policy-document file:///tmp/instance-trust.json --region "$REGION" >/dev/null
add_to_manifest iam-role condor-reportes-instance-role
aws iam attach-role-policy --role-name condor-reportes-instance-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
cat > /tmp/instance-bundle-policy.json <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:GetObjectVersion"],"Resource":["arn:aws:s3:::condor-reportes-artifacts-${ACCT}/*","arn:aws:s3:::aws-codedeploy-${REGION}/*"]}]}
EOF
aws iam put-role-policy --role-name condor-reportes-instance-role \
  --policy-name codedeploy-bundle-access --policy-document file:///tmp/instance-bundle-policy.json
aws iam create-instance-profile --instance-profile-name condor-reportes-instance-profile >/dev/null
add_to_manifest instance-profile condor-reportes-instance-profile
aws iam add-role-to-instance-profile --instance-profile-name condor-reportes-instance-profile \
  --role-name condor-reportes-instance-role
sleep 10  # instance profile propagation

cat > /tmp/codedeploy-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codedeploy.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name condor-reportes-codedeploy-role \
  --assume-role-policy-document file:///tmp/codedeploy-trust.json --region "$REGION" >/dev/null
add_to_manifest iam-role condor-reportes-codedeploy-role
aws iam attach-role-policy --role-name condor-reportes-codedeploy-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole

echo "== artifact bucket (untagged) =="
aws s3api create-bucket --bucket "condor-reportes-artifacts-${ACCT}" --region "$REGION" >/dev/null
add_to_manifest s3-bucket "condor-reportes-artifacts-${ACCT}"

echo "== ALB =="
TG_ARN=$(aws elbv2 create-target-group --region "$REGION" \
  --name condor-reportes --protocol HTTP --port 8080 --vpc-id "$VPC_ID" --target-type instance \
  --health-check-path /report --health-check-protocol HTTP \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
add_to_manifest target-group "$TG_ARN"

ALB_ARN=$(aws elbv2 create-load-balancer --region "$REGION" \
  --name condor-reportes --type application --scheme internal \
  --subnets "${APP_SUBNETS[@]}" --security-groups "$ALB_SG" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)
add_to_manifest load-balancer "$ALB_ARN"

LISTENER_ARN=$(aws elbv2 create-listener --region "$REGION" \
  --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 \
  --default-actions "Type=forward,TargetGroupArn=$TG_ARN" \
  --query 'Listeners[0].ListenerArn' --output text)
add_to_manifest listener "$LISTENER_ARN"

ALB_DNS=$(aws elbv2 describe-load-balancers --region "$REGION" --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].DNSName' --output text)
ALB_ZONE=$(aws elbv2 describe-load-balancers --region "$REGION" --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].CanonicalHostedZoneId' --output text)

echo "== Route 53 =="
cat > /tmp/reportes-dns.json <<EOF
{"Changes":[{"Action":"CREATE","ResourceRecordSet":{"Name":"reportes.condor.internal","Type":"A","AliasTarget":{"HostedZoneId":"$ALB_ZONE","DNSName":"$ALB_DNS","EvaluateTargetHealth":true}}}]}
EOF
aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch file:///tmp/reportes-dns.json >/dev/null
add_to_manifest route53-record "reportes.condor.internal"

echo "== launch template =="
AMI_ID=$(aws ssm get-parameter --region "$REGION" \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' --output text)
cat > /tmp/reportes-userdata.sh <<'USERDATA'
#!/bin/bash
dnf install -y java-17-amazon-corretto ruby wget
cd /tmp
wget https://aws-codedeploy-us-east-1.s3.us-east-1.amazonaws.com/latest/install
chmod +x ./install
./install auto
systemctl enable codedeploy-agent
systemctl start codedeploy-agent
USERDATA
USERDATA_B64=$(base64 < /tmp/reportes-userdata.sh)

cat > /tmp/reportes-lt.json <<EOF
{
  "ImageId": "$AMI_ID",
  "InstanceType": "t3.small",
  "IamInstanceProfile": {"Name": "condor-reportes-instance-profile"},
  "SecurityGroupIds": ["$INSTANCE_SG"],
  "UserData": "$USERDATA_B64"
}
EOF
LT_ID=$(aws ec2 create-launch-template --region "$REGION" \
  --launch-template-name condor-reportes \
  --launch-template-data file:///tmp/reportes-lt.json \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)
add_to_manifest launch-template "$LT_ID"

echo "== ASG (no tags) =="
SUBNET_CSV=$(IFS=,; echo "${APP_SUBNETS[*]}")
aws autoscaling create-auto-scaling-group --region "$REGION" \
  --auto-scaling-group-name condor-reportes \
  --launch-template "LaunchTemplateId=$LT_ID,Version=\$Latest" \
  --min-size 2 --max-size 2 --desired-capacity 2 \
  --vpc-zone-identifier "$SUBNET_CSV" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB --health-check-grace-period 120
add_to_manifest autoscaling-group condor-reportes

echo "== CodeDeploy =="
aws deploy create-application --region "$REGION" \
  --application-name condor-reportes --compute-platform Server >/dev/null
add_to_manifest codedeploy-application condor-reportes
CD_ROLE_ARN=$(aws iam get-role --role-name condor-reportes-codedeploy-role --query 'Role.Arn' --output text)
aws deploy create-deployment-group --region "$REGION" \
  --application-name condor-reportes \
  --deployment-group-name condor-reportes-prod \
  --service-role-arn "$CD_ROLE_ARN" \
  --auto-scaling-groups condor-reportes \
  --deployment-config-name CodeDeployDefault.OneAtATime >/dev/null
add_to_manifest codedeploy-deployment-group condor-reportes-prod

echo "== worker (untagged, no instance profile, SSM Agent disabled — PLANTED: AK-COV-02) =="
WORKER_AMI=$(aws ssm get-parameter --region "$REGION" \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' --output text)
cat > /tmp/reportes-worker-userdata.sh <<'USERDATA'
#!/bin/bash
systemctl stop amazon-ssm-agent
systemctl disable amazon-ssm-agent
echo "* * * * * root curl -s -o /dev/null http://reportes.condor.internal/report" > /etc/cron.d/reportes-worker
chmod 644 /etc/cron.d/reportes-worker
USERDATA
WORKER_ID=$(aws ec2 run-instances --region "$REGION" \
  --image-id "$WORKER_AMI" --instance-type t3.micro \
  --subnet-id "${APP_SUBNETS[0]}" --security-group-ids "$INSTANCE_SG" \
  --user-data file:///tmp/reportes-worker-userdata.sh \
  --query 'Instances[0].InstanceId' --output text)
add_to_manifest ec2-instance "$WORKER_ID"

echo "done"
echo "ALB_DNS=$ALB_DNS"
echo "TG_ARN=$TG_ARN"
echo "WORKER_ID=$WORKER_ID"
