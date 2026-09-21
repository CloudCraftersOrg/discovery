data "aws_iam_policy_document" "lbc_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lbc" {
  name               = "condor-pagos-lbc"
  assume_role_policy = data.aws_iam_policy_document.lbc_trust.json
}

# Inline, not a standalone managed policy - condor-bootstrap-access can
# PutRolePolicy but not iam:CreatePolicy (confirmed live, AccessDenied).
resource "aws_iam_role_policy" "lbc" {
  name   = "condor-pagos-lbc"
  role   = aws_iam_role.lbc.id
  policy = file("${path.module}/aws-load-balancer-controller-policy.json")
}

resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = aws_eks_cluster.pagos.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc.arn
}
