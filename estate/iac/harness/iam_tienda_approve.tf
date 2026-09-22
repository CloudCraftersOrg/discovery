data "aws_iam_policy_document" "tienda_approve_trust" {
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
      values   = ["${var.github_org}/condor-harness/.github/workflows/tienda-approve.yml@refs/heads/main"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "tienda_approve" {
  name               = "condor-harness-tienda-approve"
  assume_role_policy = data.aws_iam_policy_document.tienda_approve_trust.json
}

data "aws_iam_policy_document" "tienda_approve_access" {
  statement {
    sid       = "ApprovePendingGate"
    effect    = "Allow"
    actions   = ["codepipeline:GetPipelineState", "codepipeline:PutApprovalResult"]
    resources = ["arn:aws:codepipeline:${var.home_region}:${var.condor_account_id}:condor-tienda"]
  }
}

resource "aws_iam_role_policy" "tienda_approve_access" {
  name   = "condor-harness-tienda-approve-access"
  role   = aws_iam_role.tienda_approve.id
  policy = data.aws_iam_policy_document.tienda_approve_access.json
}
