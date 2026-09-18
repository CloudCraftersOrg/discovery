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
    ]
    resources = ["*"]
  }

  statement {
    sid       = "Route53PrivateZone"
    effect    = "Allow"
    actions   = ["route53:*"]
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
    ]
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
      "iam:AttachRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:CreateRole",
      "iam:DeleteInstanceProfile",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PassRole",
      "iam:PutRolePolicy",
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
