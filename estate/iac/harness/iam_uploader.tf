locals {
  harness_workflow_refs = [
    "${var.github_org}/condor-harness/.github/workflows/commits.yml@refs/heads/main",
    "${var.github_org}/condor-harness/.github/workflows/inventario-push.yml@refs/heads/main",
    "${var.github_org}/condor-harness/.github/workflows/tienda-approve.yml@refs/heads/main",
  ]
}

data "aws_iam_policy_document" "harness_uploader_trust" {
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
      values   = local.harness_workflow_refs
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "harness_uploader" {
  name               = "condor-harness-uploader"
  assume_role_policy = data.aws_iam_policy_document.harness_uploader_trust.json
}

data "aws_iam_policy_document" "harness_uploader_access" {
  statement {
    sid       = "LedgerUpload"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.harness_ledger.arn}/*"]
  }
}

resource "aws_iam_role_policy" "harness_uploader_access" {
  name   = "condor-harness-uploader-access"
  role   = aws_iam_role.harness_uploader.id
  policy = data.aws_iam_policy_document.harness_uploader_access.json
}
