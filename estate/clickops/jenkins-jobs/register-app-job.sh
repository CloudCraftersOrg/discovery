#!/bin/bash
# Registers a multibranch pipeline job for an app whose Jenkinsfile runs
# alongside its existing CodePipeline/GitHub Actions pipeline (Tienda,
# Pagos). Runs ON the condor-jenkins instance (localhost:8080) via SSM, not
# from the operator's machine - port 8080 is only reachable in-VPC, and
# running here means the SSH deploy key never leaves the instance. Two
# phases because the deploy key's public half has to be registered on
# GitHub (an operator action) before the "finish" phase can use the
# credential it unlocks. Scoped to just the credential + job creation -
# unlike create-jobs.sh (P1-11), this has no app-specific planted-finding
# setup to bundle in.
#
# Usage: register-app-job.sh genkey  <app>          -- generates the SSH
#                                                        keypair, prints the
#                                                        public key only
#        register-app-job.sh finish  <app> <xml-file>  -- everything else
set -euo pipefail

JENKINS_URL=http://localhost:8080
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  genkey)
    app="${2:?usage: $0 genkey <app>}"
    key_path="/tmp/${app}-deploy-key"
    ssh-keygen -t ed25519 -N '' -C "${app} read-only (Jenkins)" -f "$key_path" -q
    cat "${key_path}.pub"
    exit 0
    ;;
  finish)
    app="${2:?usage: $0 finish <app> <xml-file>}"
    xml_file="${3:?usage: $0 finish <app> <xml-file>}"
    ;;
  *) echo "usage: $0 {genkey|finish} <app> [xml-file]" >&2; exit 1 ;;
esac

key_path="/tmp/${app}-deploy-key"
yum install -y -q python3 jq >/dev/null

ADMIN_PASSWORD=$(cat /var/lib/jenkins/.admin-password)
COOKIEJAR=$(mktemp)
# The crumb is bound to the session cookie it was issued under - one shared
# cookie jar for both calls (see create-jobs.sh for the failure mode).
AUTH=(-u "admin:${ADMIN_PASSWORD}" -b "$COOKIEJAR" -c "$COOKIEJAR")
CRUMB=$(curl -s "${AUTH[@]}" "${JENKINS_URL}/crumbIssuer/api/json" | jq -r '.crumbRequestField + ":" + .crumb')

echo "== SSH credential for ${app} (read-only deploy key) =="
DEPLOY_KEY_JSON=$(python3 -c "
import json
with open('${key_path}') as f:
    key = f.read()
print(json.dumps({
    '': '0',
    'credentials': {
        'scope': 'GLOBAL',
        'id': '${app}-deploy-key',
        'username': 'git',
        'privateKeySource': {
            'value': '0',
            'privateKey': key,
            'stapler-class': 'com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey\$DirectEntryPrivateKeySource',
        },
        'passphrase': '',
        'description': '${app} read-only deploy key',
        '\$class': 'com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey',
    },
}))
")
curl -s -o /dev/null -w '%{http_code}\n' "${AUTH[@]}" -H "$CRUMB" \
  "${JENKINS_URL}/credentials/store/system/domain/_/createCredentials" \
  --data-urlencode "json=${DEPLOY_KEY_JSON}"
shred -u "$key_path"

echo "== multibranch pipeline: ${app} =="
curl -s -o /dev/null -w '%{http_code}\n' "${AUTH[@]}" -H "$CRUMB" \
  -H 'Content-Type: application/xml' \
  --data-binary "@${xml_file}" \
  "${JENKINS_URL}/createItem?name=${app}"

echo "done"
