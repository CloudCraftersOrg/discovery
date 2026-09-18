# BLOCKED-P1-03 · Account telemetry baseline

Terraform is written (`estate/iac/baseline/`) and passes `terraform validate`.
Cannot `plan`/`apply`: this task must run as `condor-bootstrap` (ADR-045 —
the whole point of the role split is keeping estate evidence under its own
CloudTrail identity), which requires `sts:AssumeRole` on `condor-*` roles.

That permission is [`CloudCraftersOrg/aws-access` PR #39](https://github.com/CloudCraftersOrg/aws-access/pull/39),
still open — `reviewDecision: REVIEW_REQUIRED`, `mergeStateStatus: BLOCKED`.
`aws-access`'s `CODEOWNERS` requires @santiacmaestre's review on every
change there; this isn't something the operator can merge around.

**Unblocks when:** PR #39 merges. Then: `aws sts assume-role --role-arn
arn:aws:iam::337058058699:role/condor-bootstrap --role-session-name
p1-03 --profile personal-aidiscovery`, export the resulting credentials,
`make plan-estate`.
