#!/usr/bin/env bash
set -euo pipefail

area="${1:-}"
case "$area" in
  estate)   expected_role="condor-bootstrap" ;;
  platform) expected_role="dp-deployer" ;;
  *)
    echo "usage: guard.sh <estate|platform>" >&2
    exit 1
    ;;
esac

if [[ -z "${CONDOR_ACCOUNT_ID:-}" ]]; then
  echo "guard.sh: CONDOR_ACCOUNT_ID is not set" >&2
  exit 1
fi

identity_json="$(aws sts get-caller-identity --output json)"
account="$(echo "$identity_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["Account"])')"
arn="$(echo "$identity_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["Arn"])')"

if [[ "$account" != "$CONDOR_ACCOUNT_ID" ]]; then
  echo "guard.sh: caller account $account is not CONDOR_ACCOUNT_ID ($CONDOR_ACCOUNT_ID)" >&2
  exit 1
fi

# Matches .../assumed-role/<role-name>/<session> for an assumed role, or
# .../role/<role-name> for a role used directly (e.g. AWSReservedSSO_*).
role_name="$(echo "$arn" | sed -nE 's#.*(assumed-role|role)/([^/]+).*#\2#p')"

if [[ "$role_name" != "$expected_role" ]]; then
  echo "guard.sh: assumed role '$role_name' does not match '$expected_role' required for area '$area'" >&2
  echo "guard.sh: caller ARN was: $arn" >&2
  exit 1
fi

echo "guard.sh: OK — $area, account $account, role $role_name"
