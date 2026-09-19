# ADR-045: this is a customer-managed allow-list, not AdministratorAccess.
# Covers what tasks P1-01/P1-03/P1-04/P1-12 need now, plus the estate-app
# surface (P1-06..P1-11) that's clearly coming next. Widen when a later task
# hits a real denial — CLAUDE.md's own stop-condition discipline expects
# exactly that, not a fully-predicted policy up front.
data "aws_iam_policy_document" "condor_bootstrap_access" {
  statement {
    sid    = "EstateCompute"
    effect = "Allow"
    actions = [
      "autoscaling:*",
      "cloudformation:*",
      "cloudwatch:*",
      "codebuild:*",
      "codeconnections:*",
      "codedeploy:*",
      "codepipeline:*",
      # AWS::CodeStarConnections::Connection (the CFN resource type) and
      # CodePipeline's PassConnection/UseConnection still check this legacy
      # prefix, not codeconnections:* above - AccessDenied against
      # condor-bootstrap itself (the caller creating the pipeline), not the
      # pipeline's own service role, on a real apply.
      "codestar-connections:*",
      "ec2:*",
      "ecr:*",
      "ecs:*",
      "eks:*",
      "elasticloadbalancing:*",
      "logs:*",
      "rds:*",
      "ssm:*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AccountTelemetry"
    effect = "Allow"
    actions = [
      "bcm-data-exports:*",
      "budgets:*",
      "ce:*",
      "cloudtrail:*",
      "compute-optimizer:*",
      "config:*",
      "cost-optimization-hub:*",
      # BCM Data Exports still calls the legacy CUR API under the hood for
      # CreateExport (cur:PutReportDefinition) - discovered as a real
      # AccessDenied on the first real apply, not predicted from docs.
      "cur:*",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "Route53PrivateZone"
    effect    = "Allow"
    actions   = ["route53:*"]
    resources = ["*"]
  }

  # No KMS statement at all until P1-06's RDS ManageMasterUserPassword hit
  # AccessDeniedException on kms:DescribeKey against the AWS-managed
  # aws/secretsmanager key - every estate task touching an AWS-managed key
  # (Secrets Manager, RDS storage encryption, SSM) needs this, not just this one.
  statement {
    sid    = "AwsManagedKeys"
    effect = "Allow"
    actions = [
      "kms:CreateGrant",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ListAliases",
      "kms:RetireGrant",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "CondorBuckets"
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::condor-*",
      "arn:aws:s3:::condor-*/*",
    ]
  }

  statement {
    sid     = "CondorSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:*"]
    resources = [
      "arn:aws:secretsmanager:*:*:secret:condor/*",
      # rds!* covers the master secret RDS creates when ManageMasterUserPassword
      # is set - CreateSecret AccessDenied on a real P1-06 apply, RDS names
      # these outside our own condor/ prefix and we don't control the name.
      "arn:aws:secretsmanager:*:*:secret:rds!*",
    ]
  }

  # Pricing API for recording hourly costs in PR writeups (P1-09's "record
  # its hourly price" and similar) — read-only, global service.
  statement {
    sid    = "PricingRead"
    effect = "Allow"
    actions = [
      "pricing:DescribeServices",
      "pricing:GetAttributeValues",
      "pricing:GetProducts",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "IamRead"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # dev.*/svc.* users are the only planted defect this identity may create
  # (CLAUDE.md #4, #9) — condor_sandbox_boundary denies every other name.
  statement {
    sid    = "PlantedUsers"
    effect = "Allow"
    actions = [
      "iam:CreateAccessKey",
      "iam:CreateUser",
      "iam:DeleteUser",
      "iam:PutUserPolicy",
      "iam:TagUser",
    ]
    resources = [
      "arn:aws:iam::*:user/dev.*",
      "arn:aws:iam::*:user/svc.*",
    ]
  }

  statement {
    sid    = "EstateRoles"
    effect = "Allow"
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:AttachRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:CreateRole",
      "iam:DeleteInstanceProfile",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PassRole",
      "iam:PutRolePolicy",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:TagRole",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = [
      "arn:aws:iam::*:role/condor-*",
      "arn:aws:iam::*:instance-profile/condor-*",
    ]
  }

  statement {
    sid       = "ServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::*:role/aws-service-role/*"]
  }
}

resource "aws_iam_policy" "condor_bootstrap_access" {
  name   = "condor-bootstrap-access"
  policy = data.aws_iam_policy_document.condor_bootstrap_access.json
}

resource "aws_iam_policy" "condor_sandbox_boundary" {
  name   = "condor-sandbox-boundary"
  policy = data.aws_iam_policy_document.condor_sandbox_boundary.json
}

data "aws_iam_policy_document" "condor_bootstrap_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.operator_principal_arn]
    }
  }
}

resource "aws_iam_role" "condor_bootstrap" {
  name                 = "condor-bootstrap"
  assume_role_policy   = data.aws_iam_policy_document.condor_bootstrap_trust.json
  permissions_boundary = aws_iam_policy.condor_sandbox_boundary.arn
  max_session_duration = 3600

  tags = {
    managed-by = "cloud-governance"
  }
}

resource "aws_iam_role_policy_attachment" "condor_bootstrap" {
  role       = aws_iam_role.condor_bootstrap.name
  policy_arn = aws_iam_policy.condor_bootstrap_access.arn
}
