# ADR-045: Bootstrap identity without AdministratorAccess

## Status

Accepted.

## Context

`P1-01` specifies `condor-bootstrap` and `dp-deployer` as AWS-managed `AdministratorAccess` plus the `condor-sandbox-boundary` permissions boundary, both trusting an operator principal. The operator here is a human's own IAM Identity Center session (`AIDiscoveryAccess`, `CloudCraftersOrg/aws-access` PR #38), scoped to `condor-*`/`dp-*` resource names on the Sandbox account. That set's `DenyAdminPolicyAttachment` statement — deliberately, by the design of every permission set in that repo — blocks attaching `AdministratorAccess`, `IAMFullAccess` or `PowerUserAccess` to anything it creates. The literal `P1-01` design cannot be built by the operator this PoC actually has.

## Decision

`condor-bootstrap` (and later `dp-deployer`) carries a customer-managed policy scoped the same way `AIDiscoveryAccess` itself is — account-wide compute (`ec2`, `rds`, `ecs`, `eks`, `ssm`, `codepipeline`, `codebuild`, `codedeploy`), `condor-*`-scoped `s3`/`iam`/`secretsmanager`/`route53`, and read+write on the account-telemetry services (`config`, `cloudtrail`, `budgets`) — plus the same `condor-sandbox-boundary`. Not "admin minus denies": an allow-list, matching how every set in `aws-access` is built.

`dp-deployer` is not created in this pass — the estate is the only thing being built. When platform work starts, it gets its own scoped policy over the `dp-*` surface, following the same pattern.

## Consequences

- `guard.sh`'s identity check (assumed role name must be `condor-bootstrap` or `dp-deployer`) still works exactly as designed — this only changes what's attached to the role, not its name or its role in the workflow.
- The two-identity separation `CLAUDE.md` §1 describes ("keep estate and platform evidence separate in CloudTrail") is preserved: `condor-bootstrap` is still a distinct principal from the human operator's own session.
- Anything a task assumes only `AdministratorAccess` can do (some AWS API this scoped policy doesn't yet cover) hits the `CLAUDE.md` §2 stop condition — "an AWS API... does not exist or behaves differently than described" — same as any other capability gap. Widen `condor-bootstrap-access` when that happens; it's a narrow, auditable diff, not a redesign.
