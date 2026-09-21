resource "aws_eks_access_entry" "pagos_deploy" {
  cluster_name  = aws_eks_cluster.pagos.name
  principal_arn = aws_iam_role.pagos_deploy.arn
}

resource "aws_eks_access_policy_association" "pagos_deploy" {
  cluster_name  = aws_eks_cluster.pagos.name
  principal_arn = aws_iam_role.pagos_deploy.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["pagos"]
  }
}
