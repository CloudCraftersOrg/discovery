#!/bin/bash
# Task P1-11. Runs ON the condor-jenkins instance (localhost:8080) via SSM,
# not from the operator's machine - port 8080 is only reachable in-VPC, and
# running here means the SSH deploy key and svc.jenkins-export's static
# keys are generated and consumed locally, never printed to the operator's
# own terminal. Two phases because the deploy key's public half has to be
# registered on GitHub (an operator action) before the "finish" phase can
# use the credential it unlocks.
#
# Usage: create-jobs.sh genkey   -- generates the SSH keypair, prints the
#                                    public key only, for `gh repo deploy-key add`
#        create-jobs.sh finish   -- everything else
set -euo pipefail

JENKINS_URL=http://localhost:8080
KEY_PATH=/tmp/condor-reportes-deploy-key
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  genkey)
    ssh-keygen -t ed25519 -N '' -C 'condor-reportes read-only (Jenkins)' -f "$KEY_PATH" -q
    cat "${KEY_PATH}.pub"
    exit 0
    ;;
  finish) ;;
  *) echo "usage: $0 {genkey|finish}" >&2; exit 1 ;;
esac

yum install -y -q python3 jq >/dev/null

ADMIN_PASSWORD=$(cat /var/lib/jenkins/.admin-password)
COOKIEJAR=$(mktemp)
# The crumb is bound to the session cookie it was issued under - fetching it
# in one curl invocation and spending it in another (each its own session,
# confirmed live: Jenkins set a fresh JSESSIONID on every unauthenticated
# connection) gets "No valid crumb was included in the request" even though
# the crumb string itself is correct. One shared cookie jar for every call.
AUTH=(-u "admin:${ADMIN_PASSWORD}" -b "$COOKIEJAR" -c "$COOKIEJAR")
CRUMB=$(curl -s "${AUTH[@]}" "${JENKINS_URL}/crumbIssuer/api/json" | jq -r '.crumbRequestField + ":" + .crumb')

post_credential() {
  local json="$1"
  curl -s -o /dev/null -w '%{http_code}\n' "${AUTH[@]}" -H "$CRUMB" \
    "${JENKINS_URL}/credentials/store/system/domain/_/createCredentials" \
    --data-urlencode "json=${json}"
}

echo "== SSH credential for condor-reportes (read-only deploy key) =="
DEPLOY_KEY_JSON=$(python3 -c "
import json
with open('${KEY_PATH}') as f:
    key = f.read()
print(json.dumps({
    '': '0',
    'credentials': {
        'scope': 'GLOBAL',
        'id': 'condor-reportes-deploy-key',
        'username': 'git',
        'privateKeySource': {
            'value': '0',
            'privateKey': key,
            'stapler-class': 'com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey\$DirectEntryPrivateKeySource',
        },
        'passphrase': '',
        'description': 'condor-reportes read-only deploy key',
        '\$class': 'com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey',
    },
}))
")
post_credential "$DEPLOY_KEY_JSON"
shred -u "$KEY_PATH"

echo "== multibranch pipeline: condor-reportes =="
curl -s -o /dev/null -w '%{http_code}\n' "${AUTH[@]}" -H "$CRUMB" \
  -H 'Content-Type: application/xml' \
  --data-binary "@${HERE}/multibranch-condor-reportes.xml" \
  "${JENKINS_URL}/createItem?name=condor-reportes"

echo "== svc.jenkins-export IAM user (PLANTED: AK-PIP-04) =="
aws iam get-user --user-name svc.jenkins-export >/dev/null 2>&1 || \
  aws iam create-user --user-name svc.jenkins-export \
    --permissions-boundary arn:aws:iam::337058058699:policy/condor-sandbox-boundary >/dev/null
# Rerunnable: an old key's secret can't be recovered (never persisted), so
# retire any existing keys and mint one fresh every run.
for old_key in $(aws iam list-access-keys --user-name svc.jenkins-export --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
  aws iam delete-access-key --user-name svc.jenkins-export --access-key-id "$old_key"
done
cat > /tmp/svc-jenkins-export-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ssm:SendCommand",
      "Resource": [
        "arn:aws:ssm:us-east-1::document/AWS-RunPowerShellScript",
        "arn:aws:ec2:us-east-1:337058058699:instance/*"
      ],
      "Condition": {
        "StringEquals": { "ssm:resourceTag/app": "facturacion" }
      }
    },
    {
      "Effect": "Allow",
      "Action": "ssm:SendCommand",
      "Resource": "arn:aws:ssm:us-east-1::document/AWS-RunPowerShellScript"
    }
  ]
}
EOF
aws iam put-user-policy --user-name svc.jenkins-export \
  --policy-name facturacion-export --policy-document file:///tmp/svc-jenkins-export-policy.json
ACCESS_KEY_JSON=$(aws iam create-access-key --user-name svc.jenkins-export)
AK_ID=$(echo "$ACCESS_KEY_JSON" | jq -r '.AccessKey.AccessKeyId')
AK_SECRET=$(echo "$ACCESS_KEY_JSON" | jq -r '.AccessKey.SecretAccessKey')

AWS_CRED_JSON=$(python3 -c "
import json
print(json.dumps({
    '': '0',
    'credentials': {
        'scope': 'GLOBAL',
        'id': 'aws-facturacion-export',
        'username': '${AK_ID}',
        'password': '${AK_SECRET}',
        'description': 'svc.jenkins-export static keys (PLANTED: AK-PIP-04)',
        '\$class': 'com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl',
    },
}))
")
post_credential "$AWS_CRED_JSON"
unset AK_SECRET AWS_CRED_JSON ACCESS_KEY_JSON

echo "== freestyle job: facturacion-nightly-export (XML never committed — AK-PIP-07) =="
curl -s -o /dev/null -w '%{http_code}\n' "${AUTH[@]}" -H "$CRUMB" \
  -H 'Content-Type: application/xml' \
  --data-binary "@${HERE}/.private/facturacion-nightly-export.xml" \
  "${JENKINS_URL}/createItem?name=facturacion-nightly-export"

echo "== dp-reader API token -> Secrets Manager =="
# The HTTP generateNewToken descriptor endpoint 403s even for an ADMINISTER
# admin acting on another user (confirmed live, empty-body 403, valid crumb)
# - it's meant for self-service, not admin-on-behalf-of. The script console
# calls the same Java API directly and isn't subject to that check.
GROOVY_SCRIPT='
import jenkins.security.ApiTokenProperty
def u = jenkins.model.Jenkins.get().getUser("dp-reader")
def prop = u.getProperty(ApiTokenProperty.class)
def result = prop.tokenStore.generateNewToken("discovery-platform")
u.save()
print(result.plainValue)
'
TOKEN=$(curl -s "${AUTH[@]}" -H "$CRUMB" -X POST \
  "${JENKINS_URL}/scriptText" --data-urlencode "script=${GROOVY_SCRIPT}")
if [ -z "$TOKEN" ]; then
  echo "token generation failed" >&2
  exit 1
fi
aws secretsmanager create-secret --region us-east-1 \
  --name condor/jenkins/dp-reader --secret-string "$TOKEN" 2>/dev/null || \
  aws secretsmanager put-secret-value --region us-east-1 \
    --secret-id condor/jenkins/dp-reader --secret-string "$TOKEN" >/dev/null
unset TOKEN

echo "done"
echo "AK_ID=$AK_ID"
