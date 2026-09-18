# ADR-045: condor-bootstrap does not hold AdministratorAccess. The operator
# session that applies this (AIDiscoveryAccess) cannot attach it to anything
# it creates — see the ADR for why, and why an allow-list is the right shape
# here rather than "admin minus denies".

data "aws_iam_policy_document" "condor_sandbox_boundary" {
  statement {
    sid       = "AllowAllInAccount"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid       = "DenyOrgAndAccount"
    effect    = "Deny"
    actions   = ["organizations:*", "account:*"]
    resources = ["*"]
  }

  # dev.* and svc.* are the only IAM users any task here is allowed to plant
  # (CLAUDE.md #4, #9) — everything else is a real escalation path.
  statement {
    sid     = "DenyCreateUserExceptPlantedPrefixes"
    effect  = "Deny"
    actions = ["iam:CreateUser"]
    not_resources = [
      "arn:aws:iam::*:user/dev.*",
      "arn:aws:iam::*:user/svc.*",
    ]
  }

  # No "protect the bootstrap state object" statement here: bootstrap uses
  # local state (versions.tf), not this bucket, so there is no such object
  # for condor-bootstrap to reach in the first place.
}
