#!/usr/bin/env bash
# Task P1-08. Clickops on purpose (CLAUDE.md #4) - no IaC, no pipeline.
# Foundational setup runs as condor-bootstrap; the ECR push and the first
# task-definition registration + service update run as dev.juan's own
# static keys, so CloudTrail records a human identity for the actual
# deploy action (PLANTED: AK-PIP-04). Run once from an instance with both
# VPC network access to Tienda's RDS (the read-only user) and docker
# (the image build) - the condor-jenkins instance already has both from
# earlier tasks.
set -euo pipefail

REGION=us-east-1
ACCOUNT_ID=337058058699
VPC_ID=vpc-06f069857cd5a3612
APP_SUBNET_IDS="subnet-07d4eaa7178b102dd,subnet-053689a1cf888e29e"
BOUNDARY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/condor-sandbox-boundary"
TIENDA_DB_ENDPOINT="condor-tienda-db.calscauowkvr.us-east-1.rds.amazonaws.com"
TIENDA_DB_SECRET_ARN="arn:aws:secretsmanager:us-east-1:337058058699:secret:rds!db-414550b3-bec9-4de3-b283-7fdb41ab6832-2iwaTt"
API_TOKEN="CONDOR-CANARY-$(python3 -c 'import uuid; print(uuid.uuid4())')"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HERE/../manifest.json"

add_to_manifest() {
  local kind="$1" id="$2"
  python3 -c "
import json
m = json.load(open('$MANIFEST'))
m['resources'].append({'kind': '$kind', 'id': '$id', 'app': 'inventario'})
json.dump(m, open('$MANIFEST', 'w'), indent=2)
"
}

echo "== dev.juan (PLANTED: AK-PIP-04) =="
aws iam create-user --user-name dev.juan --permissions-boundary "$BOUNDARY_ARN" --region "$REGION" >/dev/null
add_to_manifest iam-user dev.juan

cat > /tmp/dev-juan-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:BatchGetImage"
      ],
      "Resource": "arn:aws:ecr:${REGION}:${ACCOUNT_ID}:repository/condor-inventario"
    },
    {
      "Effect": "Allow",
      "Action": "ecs:UpdateService",
      "Resource": "arn:aws:ecs:${REGION}:${ACCOUNT_ID}:service/condor-inventario/condor-inventario"
    },
    {
      "Effect": "Allow",
      "Action": "ecs:RegisterTaskDefinition",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/condor-inventario-execution-role"
    }
  ]
}
EOF
# RegisterTaskDefinition has no cluster-scoped resource ARN or condition key
# (confirmed against AWS's own docs) - Resource "*" is the actual constraint,
# not a corner cut here. UpdateService, unlike the task's literal "on the
# Inventario cluster" wording, is scoped to the service ARN instead of a
# cluster condition - ecs:cluster isn't in RegisterTaskDefinition's request
# context, so an ArnEquals on it would silently never match either action.
aws iam put-user-policy --user-name dev.juan --policy-name inventario-deploy \
  --policy-document file:///tmp/dev-juan-policy.json --region "$REGION"

ACCESS_KEY_JSON=$(aws iam create-access-key --user-name dev.juan --region "$REGION")
DEV_JUAN_KEY=$(echo "$ACCESS_KEY_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["AccessKey"]["AccessKeyId"])')
DEV_JUAN_SECRET=$(echo "$ACCESS_KEY_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["AccessKey"]["SecretAccessKey"])')
add_to_manifest iam-access-key "$DEV_JUAN_KEY"
aws secretsmanager create-secret --region "$REGION" --name condor/harness/dev-juan \
  --secret-string "{\"access_key_id\":\"${DEV_JUAN_KEY}\",\"secret_access_key\":\"${DEV_JUAN_SECRET}\"}" >/dev/null
add_to_manifest secretsmanager-secret condor/harness/dev-juan

echo "== ECR condor-inventario (PLANTED: AK-PIP-09 - mutable tags, scan on push disabled) =="
aws ecr create-repository --repository-name condor-inventario --region "$REGION" \
  --image-tag-mutability MUTABLE \
  --image-scanning-configuration scanOnPush=false >/dev/null
add_to_manifest ecr-repository condor-inventario

echo "== read-only Postgres user on Tienda's db (PLANTED: AK-APP-02) =="
RO_PASSWORD=$(python3 -c 'import secrets,string; a=string.ascii_letters+string.digits; print("".join(secrets.choice(a) for _ in range(32)))')
TIENDA_MASTER_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "$TIENDA_DB_SECRET_ARN" --region "$REGION" \
  --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')
PGPASSWORD="$TIENDA_MASTER_PASSWORD" psql -h "$TIENDA_DB_ENDPOINT" -U tienda -d tienda <<SQL
CREATE USER inventario_ro WITH PASSWORD '${RO_PASSWORD}';
GRANT CONNECT ON DATABASE tienda TO inventario_ro;
GRANT USAGE ON SCHEMA public TO inventario_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO inventario_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO inventario_ro;
SQL
unset TIENDA_MASTER_PASSWORD
add_to_manifest postgres-role inventario_ro

INVENTARIO_DB_URL="postgresql://inventario_ro:${RO_PASSWORD}@${TIENDA_DB_ENDPOINT}:5432/tienda"
unset RO_PASSWORD
aws secretsmanager create-secret --region "$REGION" --name condor/inventario/db \
  --secret-string "$INVENTARIO_DB_URL" >/dev/null
unset INVENTARIO_DB_URL
add_to_manifest secretsmanager-secret condor/inventario/db

echo "== ECS cluster + execution role (no tags, no alarms - PLANTED: AK-APP-04) =="
aws ecs create-cluster --cluster-name condor-inventario --capacity-providers FARGATE --region "$REGION" >/dev/null
add_to_manifest ecs-cluster condor-inventario

cat > /tmp/inventario-execution-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name condor-inventario-execution-role \
  --assume-role-policy-document file:///tmp/inventario-execution-trust.json --region "$REGION" >/dev/null
aws iam attach-role-policy --role-name condor-inventario-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
cat > /tmp/inventario-execution-secrets.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:condor/inventario/db-*"
  }]
}
EOF
aws iam put-role-policy --role-name condor-inventario-execution-role --policy-name read-db-secret \
  --policy-document file:///tmp/inventario-execution-secrets.json --region "$REGION"
add_to_manifest iam-role condor-inventario-execution-role

aws logs create-log-group --log-group-name /condor/inventario --region "$REGION"
add_to_manifest log-group /condor/inventario

echo "== security group (no ingress needed - task only calls out) =="
SG_ID=$(aws ec2 create-security-group --group-name condor-inventario --description "condor-inventario task" \
  --vpc-id "$VPC_ID" --region "$REGION" --query GroupId --output text)
add_to_manifest security-group "$SG_ID"

echo "== task definition (image not pushed yet - condor-bootstrap registers rev 1) =="
cat > /tmp/inventario-taskdef.json <<EOF
{
  "family": "condor-inventario",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/condor-inventario-execution-role",
  "containerDefinitions": [
    {
      "name": "condor-inventario",
      "image": "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/condor-inventario:latest",
      "environment": [
        {"name": "DB_HOST", "value": "${TIENDA_DB_ENDPOINT}"},
        {"name": "API_TOKEN", "value": "${API_TOKEN}"}
      ],
      "secrets": [
        {"name": "DATABASE_URL", "valueFrom": "arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:condor/inventario/db"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/condor/inventario",
          "awslogs-region": "${REGION}",
          "awslogs-stream-prefix": "condor-inventario"
        }
      }
    }
  ]
}
EOF
aws ecs register-task-definition --cli-input-json file:///tmp/inventario-taskdef.json --region "$REGION" >/dev/null
add_to_manifest ecs-task-definition condor-inventario

echo "== service (desired 1, app subnets, no load balancer) =="
aws ecs create-service --cluster condor-inventario --service-name condor-inventario \
  --task-definition condor-inventario --desired-count 1 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[${APP_SUBNET_IDS}],securityGroups=[${SG_ID}],assignPublicIp=DISABLED}" \
  --region "$REGION" >/dev/null
add_to_manifest ecs-service condor-inventario

echo "== first image: build + push as dev.juan (PLANTED: AK-PIP-04 evidence) =="
sleep 10  # access key propagation
BUILD_DIR=$(mktemp -d)
# condor-inventario is private - GH_TOKEN is a short-lived token supplied by
# the operator at invocation time (e.g. `gh auth token`), never stored here.
git clone --depth 1 "https://x-access-token:${GH_TOKEN}@github.com/CloudCraftersOrg/condor-inventario.git" "$BUILD_DIR" >/dev/null
unset GH_TOKEN
pushd "$BUILD_DIR" >/dev/null

SAVED_AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
SAVED_AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
SAVED_AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"
export AWS_ACCESS_KEY_ID="$DEV_JUAN_KEY"
export AWS_SECRET_ACCESS_KEY="$DEV_JUAN_SECRET"
unset AWS_SESSION_TOKEN

REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/condor-inventario"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REPO"
docker build -t "${REPO}:latest" .
docker push "${REPO}:latest"

echo "== register rev 2 + update service, still as dev.juan =="
aws ecs register-task-definition --cli-input-json file:///tmp/inventario-taskdef.json --region "$REGION" >/dev/null
aws ecs update-service --cluster condor-inventario --service condor-inventario \
  --task-definition condor-inventario --force-new-deployment --region "$REGION" >/dev/null

export AWS_ACCESS_KEY_ID="$SAVED_AWS_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$SAVED_AWS_SECRET_ACCESS_KEY"
export AWS_SESSION_TOKEN="$SAVED_AWS_SESSION_TOKEN"
unset DEV_JUAN_KEY DEV_JUAN_SECRET
popd >/dev/null
rm -rf "$BUILD_DIR"

echo "done"
echo "SG_ID=$SG_ID"
