data "aws_iam_policy_document" "pagos_deploy_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.runner.outputs.github_oidc_provider_arn]
    }

    # AWS requires sub or job_workflow_ref, unscoped to "*", on any trust
    # policy naming this provider - confirmed live (MalformedPolicyDocument).
    # job_workflow_ref, not sub: this org's tokens embed immutable numeric
    # IDs in sub (repo:ORG@id/REPO@id:ref:...), confirmed by decoding a
    # real token; job_workflow_ref has no such suffix and additionally
    # pins the exact workflow file, not just the repo.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:job_workflow_ref"
      values   = ["${var.github_org}/condor-pagos/.github/workflows/deploy.yml@refs/heads/main"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pagos_deploy" {
  name               = "condor-pagos-deploy"
  assume_role_policy = data.aws_iam_policy_document.pagos_deploy_trust.json
}

data "aws_iam_policy_document" "pagos_deploy_access" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.pagos.arn]
  }

  statement {
    sid       = "DescribeCluster"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.pagos.arn]
  }

  statement {
    sid       = "DescribeDb"
    effect    = "Allow"
    actions   = ["rds:DescribeDBClusters"]
    resources = [aws_rds_cluster.pagos.arn]
  }

  # Aurora's own secret (rds!*, outside condor/*) - deploy.yml reads it to
  # build DATABASE_URL rather than baking a password into the chart.
  statement {
    sid       = "DbPassword"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:*:*:secret:rds!*"]
  }
}

resource "aws_iam_role_policy" "pagos_deploy_access" {
  name   = "condor-pagos-deploy-access"
  role   = aws_iam_role.pagos_deploy.id
  policy = data.aws_iam_policy_document.pagos_deploy_access.json
}

# Placeholder for infra.yml (workflow_dispatch only) - task P1-07 asks only
# for this role to exist as the contrast P1-13's laptop apply is measured
# against, not for infra.yml to be fully built out yet.
data "aws_iam_policy_document" "pagos_tf_ci_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.runner.outputs.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:job_workflow_ref"
      values   = ["${var.github_org}/condor-pagos/.github/workflows/infra.yml@refs/heads/main"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pagos_tf_ci" {
  name               = "condor-pagos-tf-ci"
  assume_role_policy = data.aws_iam_policy_document.pagos_tf_ci_trust.json
}
